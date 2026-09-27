{{/*
Auth Templates Library Chart - Helper Functions
Only labels and naming helpers; all resources are rendered by standalone templates.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "auth-templates.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "auth-templates.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "auth-templates.labels" -}}
app.kubernetes.io/name: {{ include "auth-templates.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | default .Chart.Version | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "auth-templates.chart" . }}
{{- end }}
