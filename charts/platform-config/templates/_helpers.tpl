{{/*
Expand the name of the chart.
*/}}
{{- define "platform-config.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name.
*/}}
{{- define "platform-config.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "platform-config.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Common labels for every first-party resource.
*/}}
{{- define "platform-config.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: {{ include "platform-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: inari-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Component label helper: {{ include "platform-config.componentLabels" (dict "root" . "component" "keycloak") }}
*/}}
{{- define "platform-config.componentLabels" -}}
{{ include "platform-config.labels" .root }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
PostgreSQL host used by sibling components: CNPG rw service or external.
*/}}
{{- define "platform-config.postgresHost" -}}
{{- if .Values.postgresql.enabled -}}
{{- printf "%s-rw" .Values.postgresql.clusterName -}}
{{- else -}}
{{- required "externalPostgres.host is required when postgresql.enabled=false" .Values.externalPostgres.host -}}
{{- end -}}
{{- end -}}

{{- define "platform-config.postgresPort" -}}
{{- if .Values.postgresql.enabled -}}5432{{- else -}}{{ .Values.externalPostgres.port }}{{- end -}}
{{- end -}}

{{/*
Credential secret name: created by the chart from values, or an existing
secret (e.g. synced from Vault via ESO). Contract keys: inari-uri,
openfga-uri, keycloak-username, keycloak-password.
*/}}
{{- define "platform-config.dbSecretName" -}}
{{- .Values.postgresql.auth.existingSecret | default "inari-db" -}}
{{- end -}}

{{/*
Name of the kubernetes.io/basic-auth secret (username+password keys) backing
CNPG managed.roles for a given database role. With existingSecret the chart
cannot derive it, so it comes from postgresql.auth.roleSecrets.<role>
(defaults to the in-cluster convention inari-db-role-<role>).
*/}}
{{- define "platform-config.roleSecretName" -}}
{{- if .root.Values.postgresql.auth.existingSecret -}}
{{- index .root.Values.postgresql.auth.roleSecrets .role | default (printf "inari-db-role-%s" .role) -}}
{{- else -}}
{{- printf "inari-db-role-%s" .role -}}
{{- end -}}
{{- end -}}

{{/*
Keycloak base URL resolution: bundled in-cluster service when
keycloak.enabled, otherwise the external instance's (admin/backchannel) URL.
Explicit keycloak.baseUrl always wins.
*/}}
{{- define "platform-config.keycloakBaseUrl" -}}
{{- if .Values.keycloak.baseUrl -}}
{{- .Values.keycloak.baseUrl -}}
{{- else if .Values.keycloak.enabled -}}
{{- "http://keycloak-service:8080" -}}
{{- else -}}
{{- required "keycloak.external.baseUrl is required when keycloak.enabled=false" .Values.keycloak.external.baseUrl -}}
{{- end -}}
{{- end -}}

{{/*
Keycloak admin client credentials secret + keys: bundled chart-created secret
or an external one synced from Vault.
*/}}
{{- define "platform-config.keycloakAdminSecretName" -}}
{{- if .Values.keycloak.enabled -}}
{{- "inari-keycloak-admin" -}}
{{- else -}}
{{- required "keycloak.external.adminSecret.name is required when keycloak.enabled=false" .Values.keycloak.external.adminSecret.name -}}
{{- end -}}
{{- end -}}
{{- define "platform-config.keycloakAdminClientIdKey" -}}
{{- if .Values.keycloak.enabled -}}client-id{{- else -}}{{ .Values.keycloak.external.adminSecret.clientIdKey | default "client-id" }}{{- end -}}
{{- end -}}
{{- define "platform-config.keycloakAdminClientSecretKey" -}}
{{- if .Values.keycloak.enabled -}}client-secret{{- else -}}{{ .Values.keycloak.external.adminSecret.clientSecretKey | default "client-secret" }}{{- end -}}
{{- end -}}

{{/*
Image reference: global.imageRegistry is prepended to the repository;
digest wins over tag.
Usage: {{ include "platform-config.image" (dict "root" . "image" .Values.keycloak.image) }}
*/}}
{{- define "platform-config.image" -}}
{{- $repo := .image.repository -}}
{{- with .root.Values.global.imageRegistry -}}
{{- $repo = printf "%s/%s" (. | trimSuffix "/") $repo -}}
{{- end -}}
{{- if .image.digest -}}
{{- printf "%s@%s" $repo .image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repo .image.tag -}}
{{- end -}}
{{- end -}}

{{/*
Pod-level imagePullSecrets from global.imagePullSecrets (list of secret
names). Include at pod-spec indentation.
*/}}
{{- define "platform-config.imagePullSecrets" -}}
{{- with .Values.global.imagePullSecrets }}
imagePullSecrets:
  {{- range . }}
  - name: {{ . | quote }}
  {{- end }}
{{- end }}
{{- end -}}
