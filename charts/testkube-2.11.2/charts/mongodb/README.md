# Testkube: MongoDB

Helm chart used to deploy the MongoDB needed to store states when deploying Testkube platform (Enterprise or OSS).

## Custom MongoDB Implementation

This implementation provides a **custom MongoDB image** with enhanced security and updated tools, while maintaining full compatibility with Bitnami's MongoDB Helm chart.

### Key Features

- **Enhanced Security**: 0 CRITICAL/HIGH vulnerabilities (vs 8 in official image)
- **Updated Tools**: MongoDB tools recompiled with Go 1.24 and latest dependencies
- **Security Patches**: Ubuntu 24.04 LTS with latest security patches applied
- **Bitnami Compatibility**: Full compatibility with existing Helm charts
- **Custom Entrypoint**: Handles permissions and configuration like Bitnami approach

### Security Improvements

- **Vulnerability Reduction**: From 8 HIGH vulnerabilities to 0 HIGH/CRITICAL
- **Updated Dependencies**: `golang.org/x/crypto@v0.35.0`
- **Security Patches**: Applied Ubuntu security updates
- **Package Updates**: Updated vulnerable packages (coreutils, libssl3t64, openssl, tar)

### Architecture

- **Base Image**: Official `mongo:8.0.15`
- **Tools Recompilation**: MongoDB tools built with Go 1.24
- **Security Context**: UID/GID 1001:1001 (Bitnami compatible)
- **Network Configuration**: `--bind_ip_all` for Kubernetes compatibility
- **Custom Entrypoint**: Handles directory creation and permissions

### Usage

The chart works exactly like the Bitnami MongoDB chart, with the same configuration options and values. The only difference is the custom image that provides enhanced security.

```yaml
# Example values.yaml
image:
  repository: testkube/mongodb
  tag: 8.0.15

# All other Bitnami configuration options work as expected
auth:
  enabled: false
persistence:
  enabled: true
```

### Files

- `mongo-8.dockerfile`: Custom MongoDB image with security enhancements
- `entrypoint.sh`: Custom entrypoint script following Bitnami approach
- `mongo.values.yaml`: Helm values for custom deployment
- `tiltfile`: Tilt configuration for local development

Based on Bitnami MongoDB helm chart with custom security enhancements.
