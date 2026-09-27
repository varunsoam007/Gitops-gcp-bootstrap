# Auth Templates Library Chart

A Helm library chart providing reusable OAuth2-proxy authentication templates for Istio service mesh using the aggregator pattern.

## Overview

This library chart automatically generates Istio AuthorizationPolicies and ReferenceGrants to enable OAuth2-proxy external authorization for applications behind Istio gateways.

## Architecture

Follows the same aggregator pattern as `global-templates`:
- Single entry point: `auth-templates.all`
- Declarative configuration via `values.yaml`
- Auto-generates Kubernetes resources based on configuration

## Usage

### Method 1: As a Dependency (Recommended)

Add to your application chart's `Chart.yaml`:

```yaml
dependencies:
  - name: auth-templates
    version: "1.0.0"
    repository: "file://../auth-templates"
```

In your `templates/resources.yaml`:

```yaml
{{- include "auth-templates.all" . }}
```

In your `values.yaml`:

```yaml
auth:
  enabled: true
  hostname: "myapp.k01.devm.corp.pinpetuk.net"
  requiredRoles:
    - "myapp.reader"
    - "myapp.admin"
```

### Method 2: Alongside global-templates

Most charts already use `global-templates` which has built-in auth support. Just configure the `auth` block:

```yaml
# In demo-web-app values.yaml
auth:
  enabled: true
  hostname: "demoint.k01.devm.corp.pinpetuk.net"
  requiredRoles:
    - "demo-web-app.reader"
```

The `global-templates._authorizationpolicy.yaml` and `_referencegrant.yaml` will handle the rest.

## Resources Generated

When `auth.enabled: true`, this chart generates:

### 1. AuthorizationPolicy (OAuth2 ExtAuthz)
- **Namespace**: `gateway-api` (configurable via `gatewayNamespace`)
- **Purpose**: Applies OAuth2-proxy ext_authz filter to the gateway
- **Target**: Specified hostname on shared-gateway-int

### 2. AuthorizationPolicy (Allow) - Only if requiredRoles specified
- **Namespace**: `gateway-api`
- **Purpose**: Allow based on `X-Auth-Request-Groups` header set by oauth2-proxy
- **Condition**: `request.headers[x-auth-request-groups]` matches required roles (with wildcard prefix/suffix for comma-separated values)
- **Fail-secure**: Without matching roles, Istio's implicit deny blocks the request

### 3. ReferenceGrant
- **Namespace**: `platform-auth` (configurable via `platformAuthNamespace`)
- **Purpose**: Allows HTTPRoute in app namespace to reference platform-auth service
- **Required**: For cross-namespace service references in Gateway API

## Configuration

### Required Values

| Parameter | Description | Example |
|-----------|-------------|---------|
| `auth.enabled` | Enable authentication | `true` |
| `auth.hostname` | Hostname to protect | `"myapp.k01.devm.corp.pinpetuk.net"` |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `auth.requiredRoles` | List of required Entra ID app roles (matched via X-Auth-Request-Groups header) | `[]` (no RBAC) |
| `auth.gateway` | Gateway name | `shared-gateway-int` |
| `auth.gatewayNamespace` | Gateway namespace | `gateway-api` |
| `auth.platformAuthNamespace` | OAuth2-proxy namespace | `platform-auth` |
| `auth.platformAuthServiceName` | OAuth2-proxy service name | `platform-auth` |
| `auth.excludePaths` | Paths to skip auth | See values.yaml |

## Example: Full Configuration

```yaml
auth:
  enabled: true
  hostname: "myapp.k01.devm.corp.pinpetuk.net"
  requiredRoles:
    - "myapp.reader"
    - "myapp.admin"
  gateway: shared-gateway-int
  gatewayNamespace: gateway-api
  platformAuthNamespace: platform-auth
  platformAuthServiceName: platform-auth
  excludePaths:
    - /oauth2/callback
    - /oauth2/auth
    - /oauth2/start
    - /oauth2/sign_out
    - /healthz
    - /metrics
```

## Integration with global-templates

The `auth-templates` library is compatible with `global-templates`:

1. **HTTPRoute OAuth2 callback**: `global-templates._httproute.yaml` auto-injects `/oauth2` routes when `auth.enabled: true`
2. **AuthorizationPolicies**: Both charts provide similar functionality
3. **Choose one**: Use either `global-templates` auth feature OR `auth-templates` dependency (not both)

## Differences from global-templates auth

| Feature | global-templates | auth-templates |
|---------|------------------|----------------|
| Usage | Single aggregator for all resources | Dedicated auth library |
| Integration | Built-in with deployments/services | Standalone authentication |
| Flexibility | Part of larger template library | Focused on auth only |
| Best for | Apps using global-templates | Standalone auth, custom charts |

## How It Works

### Aggregator Pattern

```yaml
# templates/resources.yaml
{{- include "auth-templates.all" . }}
```

This single line triggers:

```go
auth-templates.all
  ├─ Check if .Values.auth exists
  ├─ Check if .Values.auth.enabled == true
  └─ If true:
      ├─ auth-templates.authorizationpolicy (generates 1-3 policies)
      └─ auth-templates.referencegrant (generates ReferenceGrant)
```

### Template Hierarchy

```
auth-templates/
├── Chart.yaml (type: library)
├── values.yaml (auth_defaults)
└── templates/
    ├── resources.yaml          # Entry point: includes auth-templates.all
    ├── _helpers.tpl            # Aggregator + helper functions
    ├── _authorizationpolicy.yaml   # AuthorizationPolicy generator
    └── _referencegrant.yaml        # ReferenceGrant generator
```

## Troubleshooting

### 401 Unauthorized

**Symptom**: All requests return 401  
**Cause**: OAuth2-proxy ext_authz not configured or platform-auth service unavailable  
**Fix**: Verify platform-auth deployment and external authz configuration

### 403 Forbidden (with roles)

**Symptom**: Authenticated users get 403  
**Cause**: JWT doesn't contain required role claims  
**Fix**: Check JWT token claims match `requiredRoles` configuration

### ReferenceGrant not working

**Symptom**: HTTPRoute can't route to platform-auth  
**Cause**: ReferenceGrant in wrong namespace  
**Fix**: Ensure `platformAuthNamespace` matches actual platform-auth namespace

### No authentication applied

**Symptom**: No auth prompt, direct access allowed  
**Cause**: `auth.enabled: false` or hostname mismatch  
**Fix**: Verify `auth.enabled: true` and `auth.hostname` matches HTTPRoute hostname exactly

## License

Copyright (C) 2024 XM Cyber
