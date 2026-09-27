# Karpenter Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs that import upstream Karpenter dashboards.

## Source of truth

- Karpenter provider AWS dashboards (v1.14 docs path):
  - https://github.com/aws/karpenter-provider-aws/tree/main/website/content/en/v1.14/getting-started/getting-started-with-karpenter

## Dashboards currently imported

- `karpenter-capacity-dashboard.json`
- `karpenter-performance-dashboard.json`
- `karpenter-controllers.json`
- `karpenter-controllers-allocation.json`

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

The resources follow repo conventions:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment: `Platform Components`

Datasource mappings are included for both common patterns used by these upstream dashboards:

- `inputName: datasource`
- `inputName: DS_PROMETHEUS`

Both map to datasource `mimir`.

## Update workflow

1. Validate upstream dashboard path/version compatibility with deployed Karpenter.
2. Update URLs in this folder if upstream paths or versions change.
3. Keep datasource mappings intact unless upstream input names change.
4. Validate render:
   - `kubectl kustomize apps/grafana-shared/base/dashboards`
