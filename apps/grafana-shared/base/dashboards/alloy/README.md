# Alloy Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs generated from official Grafana Alloy rendered mixin dashboards.

## Source of truth

- Rendered dashboard JSON files:
  - https://github.com/grafana/alloy/tree/main/operations/alloy-mixin/rendered/dashboards
- Alloy mixin docs (import rendered dashboards):
  - https://grafana.com/docs/alloy/latest/troubleshoot/import-mixin-dashboards/
- Alloy mixin README:
  - https://github.com/grafana/alloy/tree/main/operations/alloy-mixin

Important: dashboards and alerts/rules should be version-aligned to the same Alloy release where possible.

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

The generated resources follow the existing repo pattern:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment: `Alloy`

## Dashboards included

- alloy-cluster-node
- alloy-cluster-overview
- alloy-controller
- alloy-logs
- alloy-loki
- alloy-opentelemetry
- alloy-otel-engine-overview
- alloy-prometheus-remote-write
- alloy-resources
