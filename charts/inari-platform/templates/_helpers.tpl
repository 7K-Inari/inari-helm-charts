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

{{/*
Credential secret name: created by the chart from values, or an existing
secret (e.g. synced from Vault via ESO). Contract keys: inari-uri,
openfga-uri, keycloak-username, keycloak-password.
*/}}
{{- define "inari-platform.dbSecretName" -}}
{{- .Values.postgresql.auth.existingSecret | default "inari-db" -}}
{{- end -}}

{{/*
Name of the kubernetes.io/basic-auth secret (username+password keys) backing
CNPG managed.roles for a given database role. With existingSecret the chart
cannot derive it, so it comes from postgresql.auth.roleSecrets.<role>
(defaults to the in-cluster convention inari-db-role-<role>).
*/}}
{{- define "inari-platform.roleSecretName" -}}
{{- if .root.Values.postgresql.auth.existingSecret -}}
{{- index .root.Values.postgresql.auth.roleSecrets .role | default (printf "inari-db-role-%s" .role) -}}
{{- else -}}
{{- printf "inari-db-role-%s" .role -}}
{{- end -}}
{{- end -}}

{{/*
Keycloak base URL resolution: bundled in-cluster service when
keycloak.enabled, otherwise the external instance's (admin/backchannel) URL.
Explicit inariServer.keycloakBaseUrl always wins.
*/}}
{{- define "inari-platform.keycloakBaseUrl" -}}
{{- if .Values.inariServer.keycloakBaseUrl -}}
{{- .Values.inariServer.keycloakBaseUrl -}}
{{- else if .Values.keycloak.enabled -}}
{{- "http://keycloak-service:8080" -}}
{{- else -}}
{{- required "keycloak.external.baseUrl is required when keycloak.enabled=false" .Values.keycloak.external.baseUrl -}}
{{- end -}}
{{- end -}}

{{/*
OIDC issuer URL resolution: explicit inariServer.oidcIssuerUrl wins, then
external.issuerUrl + /realms/<realm>, then the bundled default.
*/}}
{{- define "inari-platform.oidcIssuerUrl" -}}
{{- if .Values.inariServer.oidcIssuerUrl -}}
{{- .Values.inariServer.oidcIssuerUrl -}}
{{- else if .Values.keycloak.enabled -}}
{{- "http://keycloak-service:8080/realms/inari" -}}
{{- else -}}
{{- printf "%s/realms/inari" (required "keycloak.external.issuerUrl is required when keycloak.enabled=false" .Values.keycloak.external.issuerUrl) -}}
{{- end -}}
{{- end -}}

{{/*
Keycloak admin client credentials secret + keys: bundled chart-created secret
or an external one synced from Vault.
*/}}
{{- define "inari-platform.keycloakAdminSecretName" -}}
{{- if .Values.keycloak.enabled -}}
{{- "inari-keycloak-admin" -}}
{{- else -}}
{{- required "keycloak.external.adminSecret.name is required when keycloak.enabled=false" .Values.keycloak.external.adminSecret.name -}}
{{- end -}}
{{- end -}}
{{- define "inari-platform.keycloakAdminClientIdKey" -}}
{{- if .Values.keycloak.enabled -}}client-id{{- else -}}{{ .Values.keycloak.external.adminSecret.clientIdKey | default "client-id" }}{{- end -}}
{{- end -}}
{{- define "inari-platform.keycloakAdminClientSecretKey" -}}
{{- if .Values.keycloak.enabled -}}client-secret{{- else -}}{{ .Values.keycloak.external.adminSecret.clientSecretKey | default "client-secret" }}{{- end -}}
{{- end -}}
