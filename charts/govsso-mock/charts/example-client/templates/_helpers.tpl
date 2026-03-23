{{/* charts/govsso-mock/charts/example-client/templates/_helpers.tpl */}}

{{- define "example-client.fullname" -}}
{{- printf "%s-example-client" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "example-client.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
app.kubernetes.io/name: example-client
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end }}

{{- define "example-client.matchLabels" -}}
app.kubernetes.io/name: example-client
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}
