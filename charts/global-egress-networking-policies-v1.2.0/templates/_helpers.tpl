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
{{- if and $cfg (kindIs "map" $cfg) (hasKey $cfg "waypoint") $cfg.waypoint -}}
{{- $cfgWaypointName = $cfg.waypoint.name -}}
{{- end -}}
{{- $rootWaypointName := "" -}}
{{- if and $root.Values.waypoint (hasKey $root.Values.waypoint "name") -}}
{{- $rootWaypointName = $root.Values.waypoint.name -}}
{{- end -}}
{{- default (default "waypoint" $rootWaypointName) $cfgWaypointName -}}
{{- end }}

{{/*
Returns the configured waypoint namespace
Expects a list: [root context, config]
*/}}
{{- define "egress.waypointNamespace" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- $cfgWaypointNamespace := "" -}}
{{- if and $cfg (kindIs "map" $cfg) (hasKey $cfg "waypoint") $cfg.waypoint -}}
{{- $cfgWaypointNamespace = $cfg.waypoint.namespace -}}
{{- end -}}
{{- $rootWaypointNamespace := "" -}}
{{- if and $root.Values.waypoint (hasKey $root.Values.waypoint "namespace") -}}
{{- $rootWaypointNamespace = $root.Values.waypoint.namespace -}}
{{- end -}}
{{- default $root.Release.Namespace (default $rootWaypointNamespace $cfgWaypointNamespace) -}}
{{- end }}

{{/*
Returns namespace where waypoint-targeted policies should be created
Expects a list: [root context, config]
*/}}
{{- define "egress.policyNamespace" -}}
{{- $root := index . 0 -}}
{{- include "egress.waypointNamespace" . -}}
{{- end }}

{{/*
Returns a policy name that avoids collisions in shared waypoint namespaces
Expects a list: [root context, config, baseName]
*/}}
{{- define "egress.policyName" -}}
{{- $root := index . 0 -}}
{{- $cfg := index . 1 -}}
{{- $baseName := index . 2 -}}
{{- $policyNamespace := include "egress.policyNamespace" (list $root $cfg) -}}
{{- if ne $policyNamespace $root.Release.Namespace -}}
{{- printf "%s-%s" $root.Release.Namespace $baseName | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $baseName | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Safe resource name
*/}}
{{- define "egress.safeName" -}}
{{ . | replace "*" "wildcard" | replace "." "-" | lower }}
{{- end }}