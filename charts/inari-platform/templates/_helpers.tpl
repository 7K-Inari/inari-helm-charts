{{/*
Expand the name of the chart.
*/}}
{{- define "inari-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name.
*/}}
{{- define "inari-platform.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "inari-platform.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels for every first-party resource.
*/}}
{{- define "inari-platform.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "inari-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: inari-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Component label helper: {{ include "inari-platform.componentLabels" (dict "root" . "component" "inari-server") }}
*/}}
{{- define "inari-platform.componentLabels" -}}
{{ include "inari-platform.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
PostgreSQL host used by sibling components: CNPG rw service or external.
*/}}
{{- define "inari-platform.postgresHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- printf "%s-rw" .Values.postgresql.clusterName -}}
{{- else -}}
{{- required "externalPostgres.host is required when postgresql.enabled=false" .Values.externalPostgres.host -}}
{{- end -}}
{{- end -}}

{{- define "inari-platform.postgresPort" -}}
{{- if .Values.postgresql.enabled -}}5432{{- else -}}{{ .Values.externalPostgres.port }}{{- end -}}
{{- end -}}
