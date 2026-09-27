{{/*
Expand the name of the chart.
*/}}
{{- define "dex.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name.
*/}}
{{- define "dex.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "dex.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels for every resource.
*/}}
{{- define "dex.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "dex.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: inari-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "dex.selectorLabels" -}}
app.kubernetes.io/name: {{ include "dex.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: dex
{{- end -}}

{{/*
Service account name.
*/}}
{{- define "dex.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- .Values.serviceAccount.name | default (include "dex.fullname" .) -}}
{{- else -}}
{{- .Values.serviceAccount.name | default "default" -}}
{{- end -}}
{{- end -}}

{{/*
Dex image, pinned to appVersion unless image.tag overrides it.
*/}}
{{- define "dex.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{/*
Name + key of the object (Secret or dev ConfigMap) holding the Dex config.
Exactly one of config.existingSecret / config.devMode must be set.
*/}}
{{- define "dex.configName" -}}
{{- if .Values.config.existingSecret -}}
{{- .Values.config.existingSecret -}}
{{- else -}}
{{- printf "%s-config" (include "dex.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Validate the mutually exclusive config sources. Call from the deployment.
*/}}
{{- define "dex.validateConfig" -}}
{{- if and .Values.config.existingSecret .Values.config.devMode -}}
{{- fail "config.existingSecret and config.devMode are mutually exclusive — production uses existingSecret (ESO/Vault), devMode is kind-only" -}}
{{- end -}}
{{- if and (not .Values.config.existingSecret) (not .Values.config.devMode) -}}
{{- fail "one of config.existingSecret (ESO/Vault-synced Secret with the full Dex config.yaml) or config.devMode (kind-only mock connector) is required" -}}
{{- end -}}
{{- if not .Values.issuer -}}
{{- fail "issuer is required — the public issuer URL of this cluster's Dex (e.g. https://dex.cluster-<id>.example.org)" -}}
{{- end -}}
{{- end -}}
