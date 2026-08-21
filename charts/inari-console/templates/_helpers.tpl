{{- define "inari-console.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "inari-console.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "inari-console.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "inari-console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: inari
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "inari-console.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inari-console.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
