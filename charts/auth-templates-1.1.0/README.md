# Auth Templates Library Chart v1.1.0

Reusable Helm chart for OAuth2-proxy and M2M JWT authentication on Istio ambient mesh with Gateway API.

Auth is **per hostname** — each API endpoint gets its own set of AuthorizationPolicies scoped to its hostname. Multiple APIs behind the same shared gateway are independently protected.

## What's New in 1.1.0

**M2M (machine-to-machine) auth mode** — pure Istio JWT validation without the oauth2-proxy hop. Ideal for API endpoints called by services, not browsers.

## Modes

| Mode | Use Case | Auth Flow | Extra Hop |
|------|----------|-----------|-----------|
| `interactive` (default) | Browser apps, dashboards, UIs | oauth2-proxy ext_authz → Entra ID login redirect | Yes (oauth2-proxy) |
| `m2m` | Service-to-service APIs, ML model endpoints | Istio RequestAuthentication validates JWT natively | No |

### Interactive Mode (default, unchanged from v1.0.0)

Browser users are redirected to Entra ID login via oauth2-proxy. API callers with valid bearer tokens pass through (`skip_jwt_bearer_tokens = true` on oauth2-proxy). Role checks use the `X-Auth-Request-Groups` header set by oauth2-proxy.

### M2M Mode (new)

Callers must present a valid Entra ID JWT in the `Authorization: Bearer` header. Istio's RequestAuthentication (already deployed at the gateway) validates the token signature, issuer, and audience. No oauth2-proxy involved — lower latency, simpler flow.

Role checks use `request.auth.claims[roles]` directly from the JWT, matching Entra ID app roles.

## Istio Resources Used

Only two Istio CRD types:

1. **RequestAuthentication** — shared per gateway (already deployed on each cluster). Tells Istio "if a JWT is present, validate it against Entra ID v2.0 OIDC". Doesn't block anything on its own.
2. **AuthorizationPolicy** — per-app hostname. Enforces access rules (require valid JWT, require specific roles).

## Usage

### Kustomize helmCharts entry

Add as a separate helmChart alongside your app chart in `kustomization.yaml`:

```yaml
helmGlobals:
  chartHome: ../../../../../charts

helmCharts:
  - name: my-app-v1.0.0              # your app chart
    version: v1.0.0
    releaseName: my-app
    namespace: my-app
    valuesFile: ../../base/values-common.yaml
    additionalValuesFiles:
      - values-additional.yaml
  - name: auth-templates-1.1.0        # auth chart
    version: 1.1.0
    releaseName: my-app-auth
    namespace: my-app
    additionalValuesFiles:
      - values-additional.yaml         # shared values file
```

Both charts consume the same `values-additional.yaml`. The app chart ignores the `auth:` block, and auth-templates ignores the app-specific blocks.

### Values — Interactive (browser app)

```yaml
auth:
  enabled: true
  hostname: "myapp.k01.devm.corp.pinpetuk.net"
  requiredRoles:
    - "myapp.access"
```

### Values — M2M (API endpoint)

```yaml
auth:
  enabled: true
  mode: "m2m"
  hostname: "my-api.k01.devm.corp.pinpetuk.net"
  requiredRoles:
    - "my-api.access"
```

### Values — M2M (JWT required, no role check)

```yaml
auth:
  enabled: true
  mode: "m2m"
  hostname: "my-api.k01.devm.corp.pinpetuk.net"
```

## Resources Generated

### Interactive Mode

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| AuthorizationPolicy (CUSTOM) | gateway-api | Triggers oauth2-proxy ext_authz |
| AuthorizationPolicy (DENY) | gateway-api | Blocks without required roles (if `requiredRoles` set) |
| HTTPRoute (oauth2 callback) | app namespace | Routes `/oauth2/*` to platform-auth |
| ReferenceGrant | platform-auth | Cross-namespace service reference |

### M2M Mode

| Resource | Namespace | Purpose |
|----------|-----------|---------|
| AuthorizationPolicy (DENY) | gateway-api | Rejects requests without valid JWT |
| AuthorizationPolicy (DENY) | gateway-api | Rejects JWTs missing required roles (if `requiredRoles` set) |

No HTTPRoute, ReferenceGrant, or oauth2-proxy resources in M2M mode.

## Configuration

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `auth.enabled` | Enable authentication | `true` |
| `auth.hostname` | Hostname to protect | `"my-api.k01.devm.corp.pinpetuk.net"` |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `auth.mode` | Auth mode: `interactive` or `m2m` | `interactive` |
| `auth.requiredRoles` | Required Entra ID app roles | `[]` (any valid JWT accepted) |
| `auth.gateway` | Gateway name | `shared-gateway-int` |
| `auth.gatewayNamespace` | Gateway namespace | `gateway-api` |
| `auth.platformAuthNamespace` | OAuth2-proxy namespace (interactive only) | `platform-auth` |
| `auth.platformAuthServiceName` | OAuth2-proxy service name (interactive only) | `platform-auth` |
| `auth.excludePaths` | Paths to skip auth (interactive only) | `["/oauth2/*"]` |

## App Registration Setup (one-time per environment)

Each environment has a shared app registration that the gateway's RequestAuthentication validates JWTs against. These steps are needed once per app registration, not per API.

### 1. Token version

The app registration **must** have `requestedAccessTokenVersion: 2` in its manifest. This ensures the `aud` claim is the bare Client ID (e.g. `5cf4010f-...`) matching the RequestAuthentication audience. v1.0 tokens use a different `aud` format and will fail silently.

Check: Entra → App Registrations → {app} → Manifest → `"requestedAccessTokenVersion": 2`

### 2. Expose as API

The app registration must have an Application ID URI and a default scope exposed, otherwise callers can't request tokens scoped to it.

```bash
# set the Application ID URI
az ad app update --id {app-client-id} --identifier-uris "api://{app-client-id}"

# add a default user_impersonation scope (needed for delegated flows / az CLI testing)
az ad app update --id {app-client-id} --set api.oauth2PermissionScopes='[{"id":"{new-guid}","adminConsentDescription":"Access the API","adminConsentDisplayName":"Access API","isEnabled":true,"type":"User","userConsentDescription":"Access the API","userConsentDisplayName":"Access API","value":"user_impersonation"}]'
```

### 3. Admin consent

Grant tenant-wide admin consent so users and apps can get tokens without individual consent prompts:

```bash
az ad app permission admin-consent --id {app-client-id}
```

### 4. Pre-authorise Azure CLI (for testing with `az account get-access-token`)

Pre-authorise the Azure CLI first-party app so devs can test without consent prompts:

```bash
az ad app update --id {app-client-id} \
  --set api.preAuthorizedApplications='[{"appId":"04b07795-8ddb-461a-bbee-02f9e1bf7b46","delegatedPermissionIds":["{scope-id-from-step-2}"]}]'
```

Then devs can test with:

```bash
TOKEN=$(az account get-access-token --resource {app-client-id} --query accessToken -o tsv)
curl -H "Authorization: Bearer $TOKEN" https://my-api.k01.devm.corp.pinpetuk.net/
```

## Per-API App Role Setup

Each API endpoint needs an app role on the per-env app registration for role-based access control.

### 1. Create the app role

The role **must** have `allowedMemberTypes` that includes `"Application"` for M2M callers (client_credentials tokens). Use `["User", "Application"]` if both users and services need the role.

```bash
# get existing roles first, then append
az ad app show --id {app-client-id} --query "appRoles" -o json

# update with new role added (must include ALL existing roles)
az ad app update --id {app-client-id} --app-roles '[
  ...existing roles...,
  {
    "allowedMemberTypes": ["User", "Application"],
    "displayName": "My API Access",
    "description": "Access to My API",
    "id": "{new-guid}",
    "isEnabled": true,
    "value": "my-api.access"
  }
]'
```

> **Important**: if the role only has `["User"]`, M2M (client_credentials) tokens will NOT get the `roles` claim — this fails silently. Always include `"Application"` for M2M use cases.

### 2. Assign the role to callers

- **Users/groups**: Entra → Enterprise Applications → {app} → Users and groups → Add
- **Service principals / managed identities**: Entra → Enterprise Applications → {app} → Users and groups → Add → select the SPN/MI

## How It Works (M2M Flow)

```
Caller (SPN / Managed Identity / User)
  │
  │ 1. Get token from Entra ID
  │    - SPN: POST /oauth2/v2.0/token (client_credentials)
  │    - MI: GET IMDS token endpoint
  │    - User: az account get-access-token
  │
  │ 2. Call API with Authorization: Bearer {JWT}
  ▼
shared-gateway-int (Istio Gateway)
  │
  │ 3. RequestAuthentication validates JWT:
  │    - Signature via JWKS (Entra ID OIDC discovery)
  │    - Issuer: login.microsoftonline.com/{tenant}/v2.0
  │    - Audience: per-env app registration client ID
  │
  │ 4. jwt-required AuthorizationPolicy (DENY):
  │    notRequestPrincipals → no valid JWT = 403
  │
  │ 5. deny-roles AuthorizationPolicy (DENY):
  │    claims[roles] notValues → missing role = 403
  │
  ▼
App Pod (zero auth in application code)
```

## Per-Environment Audiences

| Environment | Audience (App Registration Client ID) |
|-------------|--------------------------------------|
| devm | `5cf4010f-3af9-4d3f-8581-19233dda0243` |
| tstm | `b99699c9-2b75-4c04-9ab2-6f63cec2d9e2` |
| prdm | `e21175bb-f575-4afb-bcc7-2d28943c2564` |

Callers request tokens with `scope: api://{audience}/.default`.

## Caller Auth Methods

Any system on the corp network can authenticate using one of these methods:

### 1. Service Principal + Client Credentials

Best for dedicated integrations where you control the caller.

```bash
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token" \
  -d "client_id={caller-client-id}" \
  -d "client_secret={caller-secret}" \
  -d "scope=api://{audience}/.default" \
  -d "grant_type=client_credentials" \
  | jq -r .access_token)
```

### 2. Managed Identity (Azure-hosted callers)

Zero secrets — use IMDS on Azure VMs, AKS, App Service etc. The MI must have the app role assigned.

```bash
TOKEN=$(curl -s -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource={audience-client-id}" \
  | jq -r .access_token)
```

### 3. Bearer pass-through (interactive mode only)

If a caller already has a valid Entra ID JWT, it can call interactive-mode endpoints directly — oauth2-proxy's `skip_jwt_bearer_tokens = true` bypasses the login redirect.

## Migration from v1.0.0

v1.1.0 is fully backwards compatible. Existing interactive-mode apps need no changes — just update the chart reference from `auth-templates-1.0.0` to `auth-templates-1.1.0`.

**Note**: if your app chart uses global-templates < 1.16.14, it may still generate its own AuthorizationPolicies that conflict. Bump to global-templates >= 1.16.14 where auth resources were removed from the library chart.
