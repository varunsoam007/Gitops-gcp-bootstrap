# Kubernetes Core Dashboards (Grafana Operator)

This folder contains GrafanaDashboard CRs that import official Grafana community dashboards for Kubernetes cluster and node health.

These dashboards are provisioned through Grafana Operator and are part of the shared dashboards kustomization.

## Source of truth

- Grafana dashboard catalog:
  - https://grafana.com/grafana/dashboards/
- Dashboard JSON/API endpoint format:
  - https://grafana.com/api/dashboards/<id>/revisions/<revision>/download

## Dashboards currently pinned in this folder

- Node Exporter Full
  - ID: `1860`
  - Revision: `45`
  - File: `kubernetes-node-exporter-full.yaml`
- Kubernetes / Views / Global
  - ID: `15757`
  - Revision: `43`
  - File: `kubernetes-views-global.yaml`
- Kubernetes / Views / Nodes
  - ID: `15759`
  - Revision: `40`
  - File: `kubernetes-views-nodes.yaml`
- Kubernetes / Views / Namespaces
  - ID: `15758`
  - Revision: `46`
  - File: `kubernetes-views-namespaces.yaml`
- Kubernetes / Views / Pods
  - ID: `15760`
  - Revision: `39`
  - File: `kubernetes-views-pods.yaml`

## Why these are in GrafanaDashboard CRs

This repo provisions dashboards through Grafana Operator (GrafanaDashboard resources), not by manual UI import.

The resources follow the existing repo pattern:

- `dashboards: "grafana"` label
- `instanceSelector.matchLabels.dashboards: "grafana"`
- `argocd.argoproj.io/sync-options: ServerSideApply=true`
- Folder assignment via `folderRef: kubernetes-core`
- Datasource mapping via `spec.datasources`:
  - `inputName: DS_PROMETHEUS`
  - `datasourceName: mimir`

## Update workflow (for future agents)

When updating this bundle, keep all dashboard revisions aligned in one change and validate render before commit.

1. Decide which dashboard(s) to update and target revision(s).
2. Confirm the new revision exists on grafana.com.
3. Update `spec.grafanaCom.revision` in the corresponding file(s) in this folder.
4. Keep datasource mapping unchanged unless the imported dashboard input names change.
5. Verify folder and selector conventions are unchanged:
   - `folderRef: kubernetes-core`
   - `dashboards: "grafana"` labels/selectors
6. Validate render:
   - `kubectl kustomize apps/grafana-shared/base/dashboards`
7. If dashboards change expected variables/queries, smoke test in Grafana after Argo sync.
8. Commit as one logical dashboard-bundle update.

## Notes

- These are remote imports (`spec.grafanaCom`), not embedded JSON snapshots.
- If grafana.com content changes unexpectedly at the same revision, pinning by ID+revision still provides deterministic fetch behavior from the API endpoint.
- Keep this README updated whenever IDs/revisions are changed.

## Files in this folder

- `folder-kubernetes-core.yaml`: Grafana folder resource.
- `kubernetes-node-exporter-full.yaml`: Official Node Exporter Full import.
- `kubernetes-views-global.yaml`: Official Kubernetes global view import.
- `kubernetes-views-nodes.yaml`: Official Kubernetes nodes view import.
- `kubernetes-views-namespaces.yaml`: Official Kubernetes namespaces view import.
- `kubernetes-views-pods.yaml`: Official Kubernetes pods view import.
- `kustomization.yaml`: Resource list consumed by parent dashboards kustomization.
