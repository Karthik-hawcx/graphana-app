{{/*
Expand the name of the chart.
*/}}
{{- define "hawcx-monitoring.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hawcx-monitoring.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "hawcx-monitoring.namespace" -}}
{{ .Values.namespace | default "monitoring" }}
{{- end }}
