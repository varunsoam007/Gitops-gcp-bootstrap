{{/*
Returns the namespace where the chart is deployed
*/}}
{{- define "egress.namespace" -}}
{{- .Release.Namespace -}}
{{- end }}

{{/*
Returns the configured waypoint name
Expects a list: [root context, config]
*/}}
{{- define "egress.waypointName" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- $cfgWaypointName := "" -}}
{{- if $cfg.waypoint -}}
{{- $cfgWaypointName = $cfg.waypoint.name -}}
{{- end -}}
{{- default (default "waypoint" $root.Values.waypoint.name) $cfgWaypointName -}}
{{- end }}

{{/*
Returns the configured waypoint namespace
Expects a list: [root context, config]
*/}}
{{- define "egress.waypointNamespace" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- $cfgWaypointNamespace := "" -}}
{{- if $cfg.waypoint -}}
{{- $cfgWaypointNamespace = $cfg.waypoint.namespace -}}
{{- end -}}
{{- $rootWaypointNamespace := "" -}}
{{- if $root.Values.waypoint -}}
{{- $rootWaypointNamespace = $root.Values.waypoint.namespace -}}
{{- end -}}
{{- default $root.Release.Namespace (default $rootWaypointNamespace $cfgWaypointNamespace) -}}
{{- end }}

{{/*
Returns true if waypoint is in the same namespace as the release
Expects a list: [root context, config]
*/}}
{{- define "egress.waypointIsSameNamespace" -}}
{{- $root := index . 0 -}}
{{- $waypointNs := include "egress.waypointNamespace" . -}}
{{- eq $waypointNs $root.Release.Namespace -}}
{{- end }}

{{/*
Safe resource name
*/}}
{{- define "egress.safeName" -}}
{{ . | replace "*" "wildcard" | replace "." "-" | lower }}
{{- end }}

{{/*
Returns the waypoint Gateway name.
If waypointResources.gateway.name is set, uses that.
Otherwise falls back to waypoint.name, or auto-generates <release-namespace>-waypoint.
*/}}
{{- define "global-networking-policies.waypointName" -}}
{{- $waypoint := .Values.waypoint | default dict -}}
{{- $resources := .Values.waypointResources | default dict -}}
{{- $gateway := $resources.gateway | default dict -}}
{{- if $gateway.name -}}
{{- $gateway.name -}}
{{- else if and ($resources.enabled | default true) (or (not $waypoint.name) (eq $waypoint.name "waypoint")) -}}
{{- printf "%s-waypoint" .Release.Namespace -}}
{{- else -}}
{{- $waypoint.name | default "waypoint" -}}
{{- end -}}
{{- end -}}

{{/*
Returns the waypoint ConfigMap name.
*/}}
{{- define "global-networking-policies.waypointConfigMapName" -}}
{{- $resources := .Values.waypointResources | default dict -}}
{{- $configMap := $resources.configMap | default dict -}}
{{- $infrastructure := ($resources.gateway | default dict).infrastructure | default dict -}}
{{- $parametersRef := $infrastructure.parametersRef | default dict -}}
{{- if $configMap.name -}}
{{- $configMap.name -}}
{{- else if $parametersRef.name -}}
{{- $parametersRef.name -}}
{{- else -}}
gw-options-waypoint
{{- end -}}
{{- end -}}

{{/*
Returns the waypoint Telemetry resource name.
*/}}
{{- define "global-networking-policies.waypointTelemetryName" -}}
{{- $resources := .Values.waypointResources | default dict -}}
{{- $telemetry := $resources.telemetry | default dict -}}
{{- if $telemetry.name -}}
{{- $telemetry.name -}}
{{- else -}}
{{- printf "%s-access-logs" (include "global-networking-policies.waypointName" .) -}}
{{- end -}}
{{- end -}}