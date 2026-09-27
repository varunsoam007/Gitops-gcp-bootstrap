# Mimir Alert Rules

Curated PromQL alerting rules evaluated by the Mimir ruler. Alerts route through Mimir Alertmanager → prometheus-msteams → Microsoft Teams (Power Automate Workflow webhook).

Source: [awesome-prometheus-alerts](https://github.com/samber/awesome-prometheus-alerts), tuned for our Karpenter/spot node environment.

## Official Mimir mixin references

For the official Grafana Mimir dashboard/alert/rule contract and complete rule inventory, use:

- Install dashboards and alerts:
	- https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/installing-dashboards-and-alerts/
- Monitoring requirements (labels, scrape behavior):
	- https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/requirements/
- Compiled mixin artifacts:
	- Dashboards: https://github.com/grafana/mimir/tree/main/operations/mimir-mixin-compiled/dashboards
	- Recording rules: https://github.com/grafana/mimir/blob/main/operations/mimir-mixin-compiled/rules.yaml
	- Alerts: https://github.com/grafana/mimir/blob/main/operations/mimir-mixin-compiled/alerts.yaml
- Mixin source:
	- Recording rules: https://github.com/grafana/mimir/blob/main/operations/mimir-mixin/recording_rules.libsonnet
	- Alerts: https://github.com/grafana/mimir/blob/main/operations/mimir-mixin/alerts.libsonnet

Important: dashboards, recording rules, and alerts should be version-aligned.

## Pipeline

```
mimir-ruler-rules ConfigMap → Mimir Ruler → Mimir Alertmanager → prometheus-msteams → Teams
```

Rules are mounted into the ruler pod at `/etc/mimir-rules/anonymous/` via the ConfigMap defined in `mimir-ruler-rules.yaml`.

This ConfigMap now includes:

- Curated platform alerts.
- Mimir dashboard compatibility recording rules (for example `cluster_job_route:cortex_request_duration_seconds_bucket:sum_rate`) required by official Mimir dashboards.

## Alertmanager Routing

| Setting | Value | Notes |
|---------|-------|-------|
| `group_by` | `['alertname', 'namespace']` | Groups related alerts together |
| `group_wait` | `1m` | Wait before sending first notification for a new group |
| `group_interval` | `1h` | Wait between notifications for an existing group |
| `repeat_interval` | `12h` | Wait before re-sending a firing alert |

These values are set per-environment in `envs/<env>/values-additional.yaml`.

## Rules Summary

### kubernetes-nodes (5 rules)

Each alert is deduped per `(cluster, node)` so exporter restarts don't double-fire.

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesNodeNotReady` | critical | 10m | Node reporting `Ready=false`. |
| `KubernetesNodeMemoryPressure` | critical | 5m | Kubelet flagging memory pressure on the node. |
| `KubernetesNodeDiskPressure` | critical | 5m | Kubelet flagging disk pressure (ephemeral / image fs). |
| `KubernetesNodeNetworkUnavailable` | critical | 5m | CNI hasn't come up or the node lost its pod network. |
| `KubernetesNodeOutOfPodCapacity` | warning | 15m | Node is running >90% of its allocatable pod count. Previous expression used `pod_template_hash=""` which matched nothing; now just `count(kube_pod_info) / allocatable pods`. |

### kubernetes-pods (3 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesContainerOomKiller` | warning | 0m | A container was OOMKilled in the last 10 minutes. Deduped per pod/container so one bad pod = one alert, not N. |
| `KubernetesPodNotHealthy` | warning | 1h | Pod stuck in Pending/Unknown/Failed for an hour. **Commented out** — controller-replaced pods leave stale series that keep this firing forever. |
| `KubernetesPodCrashLooping` | warning | 15m | Pod has restarted more than 5 times in 15m. Deduped per pod/container. |

### kubernetes-workloads (5 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesDeploymentReplicasMismatch` | warning | 30m | Deployment's available replicas don't match spec for 30m. |
| `KubernetesStatefulsetDown` | warning | 15m | StatefulSet has ready replicas < desired. |
| `KubernetesStatefulsetReplicasMismatch` | warning | 30m | StatefulSet replica count drifting from spec for 30m. |
| `KubernetesDaemonsetRolloutStuck` | warning | 30m | DaemonSet rollout not progressing — pods desired but not becoming ready. |
| `KubernetesDaemonsetMisscheduled` | warning | 30m | DaemonSet pods running on nodes they shouldn't be on. Suppressed while a rollout is still in progress (RolloutStuck owns that case). |

### kubernetes-jobs (2 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesJobFailed` | warning | 15m | A Job has failed pods and was created within the last 6h (avoids re-firing on ancient failures). |
| `KubernetesCronjobFailing` | warning | 1h | CronJob's last scheduled run is newer than its last successful run, and it's not currently active or suspended. |

### kubernetes-storage (3 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesPersistentvolumeclaimPending` | warning | 15m | PVC sat in Pending — usually a CSI / storage-class problem. |
| `KubernetesPersistentvolumeError` | critical | 10m | PV went to Failed or stuck Pending. |
| `KubernetesVolumeOutOfDiskSpace` | warning | 10m | Mounted volume has less than 10% free. `for:` pushed out to 10m so snapshot and WAL churn don't flap it. |

### kubernetes-apiserver (3 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KubernetesApiServerErrors` | critical | 2m | >3% of apiserver requests returning 5xx. |
| `KubernetesApiClientErrors` | warning | 2m | >1% of apiserver requests returning 4xx/5xx to a client. |
| `KubernetesApiServerLatency` | warning | 30m | API server p99 latency >10s. Expression was broken — `histogram_quantile` was missing `le` in `by()` and returned NaN. `LIST` verbs are excluded because argocd/operator list churn was the entire firing population. |

### cert-manager (3 rules)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `CertManagerCertExpiringSoon` | warning | 1h | Certificate has less than 21 days left before expiry. |
| `CertManagerCertNotReady` | critical | 10m | Certificate condition Ready != True. |
| `CertManagerHittingRateLimits` | critical | 5m | cert-manager getting HTTP 429s from ACME — something is spamming issuance. |

### argocd (2 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `ArgocdServiceNotSynced` | warning | 15m | Application stuck OutOfSync for 15m. Deduped so the argo-cd controller pod label doesn't fracture AM grouping. |
| `ArgocdServiceUnhealthy` | warning | 15m | Application stuck in a non-Healthy state for 15m. |

### coredns (1 rule)

| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `CorednsPanicCount` | critical | 1m | CoreDNS has panicked in the last 5m. Range widened from 1m to 5m so Mimir's eval interval doesn't miss the spike. |

### grafana-alloy (6 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `AlloyUnhealthyComponents` | warning | 15m | One or more Alloy components reporting a non-healthy status. Check the Alloy UI for the offending `component_path`. |
| `AlloySlowComponentEvaluations` | warning | 15m | A component is taking too long to evaluate — usually a slow scrape target, a blocked exporter, or a config bug. |
| `AlloyRemoteWriteFailures` | warning | 10m | More than 1% of samples are failing to ship to Mimir. Could be Mimir rejecting writes (limits/auth) or the endpoint being unreachable. |
| `AlloyRemoteWriteBehind` | warning | 10m | Pending sample backlog >20k. Alloy can't keep up with shipping — Mimir is too slow or Alloy is under-resourced. |
| `AlloyRemoteWriteStalled` | critical | 5m | Last successful remote-write send is older than 10 minutes. Write path is stuck and sample age is approaching rejection window. |
| `AlloyRemoteWriteDroppingSamples` | warning | 10m | Samples being dropped on the way to Mimir. WAL is full or shards overwhelmed — active data loss. |

### mimir-self (9 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `MimirIngesterUnhealthy` | critical | 5m | An ingester is reporting Unhealthy in the hash ring. Writes for its tokens will fail. |
| `MimirIngesterOOMKilled` | critical | 0m | A Mimir ingester was OOMKilled in the last 10m. Immediate action needed before quorum loss. |
| `MimirRequestErrors` | critical | 15m | >1% 5xx on any Mimir route (ignoring 529/598 client-side rate-limits). |
| `MimirDiscardingRateLimitedSamples` | critical | 5m | Mimir is discarding samples with reason `rate_limited`; ingestion headroom is insufficient for current/replay load. |
| `MimirBadRuntimeConfig` | critical | 5m | Runtime config reload failed — Mimir is still running on its last known-good config. |
| `MimirRulerTooManyFailedPushes` | critical | 15m | The ruler is evaluating rules but can't push the results back to ingesters — recorded metrics and alerts go missing. |
| `MimirRulerMissedEvaluations` | warning | 10m | >1% of rule evaluations are being skipped — usually ruler overload. |
| `MimirIngesterReachingSeriesLimit` | warning | 3h | Ingester >80% of its `max_series` limit. Tune limits or add replicas before it starts rejecting writes. |
| `MimirCompactorHasNotSuccessfullyRunCompaction` | critical | 1h | No successful compaction in 24h. Long-term storage grows without being deduped/compacted. |

### loki (4 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `LokiRequestErrors` | critical | 15m | >10% 5xx on any Loki route. |
| `LokiRequestPanics` | critical | 0m | A Loki component hit a panic in the last 10m — expect a crash loop. |
| `LokiTooManyCompactorsRunning` | warning | 5m | More than one compactor running at a time — they'll race on the shared index. |
| `LokiCompactorHasNotSuccessfullyRunCompaction` | critical | 1h | Index compaction hasn't completed in 3h. Query performance and retention will degrade. |

### cnpg (7 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `CNPGReplicationLag` | warning | 5m | Standby more than 5 minutes behind the primary. |
| `CNPGReplicaFailingReplication` | critical | 5m | Replica is in recovery mode but the WAL receiver isn't running — replication is broken. |
| `CNPGArchiveFailing` | critical | 5m | WAL archiving (Barman/S3) is failing. PITR backups at risk. |
| `CNPGLongRunningTransaction` | warning | 5m | A query has been open >5m. Blocks VACUUM and can hold row locks. |
| `CNPGBackendsWaiting` | warning | 5m | More than 300 backends stuck waiting for locks. |
| `CNPGXidAge` | warning | 5m | Transaction ID age >300M — autovacuum falling behind, wraparound risk. |
| `CNPGDatabaseDeadlocks` | warning | 5m | More than 10 deadlock conflicts. Usually application lock-ordering issue. |

### istio (4 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `IstioHigh5xxRate` | warning | 10m | A destination workload is getting >5% 5xx responses measured at the receiving sidecar. |
| `IstioHighLatency` | warning | 15m | p99 request duration >5s at the destination sidecar. |
| `IstioPilotPushErrors` | critical | 10m | Istiod is failing to push xDS config to >5% of sidecars. Sidecars run on stale or broken config. |
| `IstiodDown` | critical | 5m | No istiod replica is reporting up. New sidecars can't bootstrap config. |

### external-secrets (3 rules)



| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `ExternalSecretNotReady` | warning | 15m | Any `ExternalSecret` with Ready=False for 15m — secret contents are stale. |
| `ClusterSecretStoreNotReady` | critical | 10m | The provider (Azure KeyVault) is unreachable — no ExternalSecret on this cluster can sync. |
| `ExternalSecretSyncErrors` | warning | 15m | Sync calls to the provider are failing repeatedly. |

### karpenter (4 rules)


| Alert | Severity | For | Description |
|-------|----------|-----|-------------|
| `KarpenterNodePoolNearLimit` | warning | 30m | NodePool >90% of its CPU or memory limit. Pods may start going unschedulable. |
| `KarpenterDisruptionQueueBacklog` | warning | 30m | Disruption queue backed up >30m — consolidation / expiry not progressing. |
| `KarpenterNodePoolErrors` | warning | 15m | NodeClaims being disrupted for non-routine reasons (not consolidation/expiration/drift/empty/underutilized) — usually health or interruption. |
| `KarpenterControllerDown` | critical | 10m | Karpenter controller not up — no new nodes will be provisioned. |
