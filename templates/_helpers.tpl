{{/*
Expand the name of the chart.
*/}}
{{- define "netbird.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "netbird.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "netbird.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "netbird.labels" -}}
helm.sh/chart: {{ include "netbird.chart" . }}
{{ include "netbird.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "netbird.selectorLabels" -}}
app.kubernetes.io/name: {{ include "netbird.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "netbird.serviceAccountName" -}}
{{- if .Values.global.serviceAccount.create }}
{{- default (include "netbird.fullname" .) .Values.global.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.global.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "netbird.stunPort" -}}
{{- .Values.global.server.stun.port | default .Values.global.server.stun_port | default 3478 }}
{{- end }}

{{/*
Name of the Secret holding config.yaml. Defaults to the chart-managed Secret,
or the user-supplied one when global.server.existingConfigSecret is set.
*/}}
{{- define "netbird.configSecretName" -}}
{{- default (printf "%s-config" (include "netbird.fullname" .)) .Values.global.server.existingConfigSecret }}
{{- end }}

{{/*
server.auth.issuer. Dex serves its own discovery document under this, so it has
to be a URL on our domain rather than an upstream provider's.
*/}}
{{- define "netbird.authIssuer" -}}
{{- .Values.global.auth.issuerUrl | default (printf "https://%s/oauth2" .Values.global.domain.global) -}}
{{- end -}}

{{/*
Shared with the existingConfigSecret guard in secret.yaml, which compares the
result against the shipped default to tell "set by the user" from "not set".
*/}}
{{- define "netbird.reverseProxy" -}}
{{- $rp := dict -}}
{{- range $k, $v := (.Values.global.server.reverseProxy | default dict) -}}
{{- if not (empty $v) }}{{- $_ := set $rp $k $v -}}{{- end -}}
{{- end -}}
{{- toYaml $rp -}}
{{- end -}}

{{/*
These configure NetBird's own embedded Dex, never an upstream provider, so a
foreign host renders fine and then fails at login. Caught here instead.
*/}}
{{- define "netbird.validateAuthHost" -}}
{{- $domain := .Values.global.domain.global -}}
{{- if $domain -}}
{{- range $key := (list "authority" "issuerUrl") -}}
{{- $val := index $.Values.global.auth $key -}}
{{- if $val -}}
{{- $host := (splitList ":" (urlParse $val).host) | first -}}
{{- if and $host (ne $host $domain) -}}
{{- fail (printf "global.auth.%s is %q, but it configures NetBird's own embedded Dex, which always issues at https://%s/oauth2. A foreign host leaves the dashboard and the server on different providers: login succeeds, then the token is rejected. To use an external provider, unset global.auth.authority/clientId/audience and add it as a Dex connector - see Authentication in the README." $key $val $domain) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Fail on an extra_env name the chart already sets, or one set twice.

Not defensive duplication of what Kubernetes checks: a duplicate is silent under
client-side apply - last one wins, only the API server warns - and the dashboard
exits when an AUTH_* it needs is empty, so overriding one there costs a startup
with nothing pointing at the cause. Server-side apply does reject duplicates,
loudly, but only installs that use it.

Call with (dict "path" "server.extra_env" "env" <list> "reserved" <dict of name -> the value that sets it>).
*/}}
{{- define "netbird.validateExtraEnv" -}}
{{- $path := .path -}}
{{- $reserved := default dict .reserved -}}
{{- $seen := dict -}}
{{- range (default (list) .env) -}}
{{- $name := .name | default "" -}}
{{- if $name -}}
{{- if hasKey $reserved $name -}}
{{- fail (printf "%s sets %s, which this chart already sets from %s. Change it there instead." $path $name (index $reserved $name)) -}}
{{- end -}}
{{- if hasKey $seen $name -}}
{{- fail (printf "%s sets %s twice. A container's env is keyed by name, so the second entry silently wins - keep one." $path $name) -}}
{{- end -}}
{{- $_ := set $seen $name true -}}
{{- end -}}
{{- end -}}
{{- end -}}
