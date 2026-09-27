{{- define "global-ingress-networking-policies.waypointName" -}}
{{- $waypoint := .Values.waypoint | default dict -}}
{{- $resources := .Values.waypointResources | default dict -}}
{{- $gateway := $resources.gateway | default dict -}}
{{- if $gateway.name -}}
{{- $gateway.name -}}
{{- else if and $resources.enabled (or (not $waypoint.name) (eq $waypoint.name "waypoint")) -}}
{{- printf "%s-waypoint" .Release.Namespace -}}
{{- else -}}
{{- $waypoint.name | default "waypoint" -}}
{{- end -}}
{{- end -}}

{{- define "global-ingress-networking-policies.waypointConfigMapName" -}}
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

{{- define "global-ingress-networking-policies.waypointTelemetryName" -}}
{{- $resources := .Values.waypointResources | default dict -}}
{{- $telemetry := $resources.telemetry | default dict -}}
{{- if $telemetry.name -}}
{{- $telemetry.name -}}
{{- else -}}
{{- printf "%s-access-logs" (include "global-ingress-networking-policies.waypointName" .) -}}
{{- end -}}
{{- end -}}