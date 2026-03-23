{{/*
charts/govsso-mock/templates/_helpers.tpl
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "govsso-mock.name" -}}
{{- include "common.names.name" . }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "govsso-mock.fullname" -}}
{{- include "common.names.fullname" . }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "govsso-mock.chart" -}}
{{- include "common.names.chart" . }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "govsso-mock.labels" -}}
{{- include "common.labels.standard" (dict "customLabels" .Values.commonLabels "context" $) }}
{{- end }}

{{/*
Selector / match labels
*/}}
{{- define "govsso-mock.matchLabels" -}}
{{- include "common.labels.matchLabels" (dict "customLabels" .Values.commonLabels "context" $) }}
{{- end }}

{{/*
Return the ServiceAccount name to use.
*/}}
{{- define "govsso-mock.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
  {{- default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else }}
  {{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate required values at render time.
Called from templates that need the required fields populated.
*/}}
{{- define "govsso-mock.validateRequiredValues" -}}
{{- if not .Values.image.repository -}}
  {{- fail "image.repository is required and must not be empty" -}}
{{- end -}}
{{- if and (not .Values.image.tag) (not .Values.image.digest) -}}
  {{- fail "either image.tag or image.digest is required and must not be empty" -}}
{{- end -}}
{{- if not .Values.tls.existingSecret -}}
  {{- fail "tls.existingSecret is required and must not be empty" -}}
{{- end -}}
{{- if not .Values.idToken.existingSecret -}}
  {{- fail "idToken.existingSecret is required and must not be empty" -}}
{{- end -}}
{{- end -}}
