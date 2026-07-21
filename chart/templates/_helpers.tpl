{{/* Stable chart identity. */}}
{{- define "zinc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The one and only service-tree label/annotation prefix. */}}
{{- define "zinc.labelPrefix" -}}
{{- required "labelPrefix is required" .Values.labelPrefix | trimSuffix "/" -}}
{{- end -}}

{{/* Validate the base LPSM projection. Platform is sourced from the release namespace. */}}
{{- define "zinc.validateServiceTree" -}}
{{- $platform := required "serviceTree.platform is required" .Values.serviceTree.platform -}}
{{- $_ := required "serviceTree.service is required" .Values.serviceTree.service -}}
{{- $_ := required "serviceTree.module is required" .Values.serviceTree.module -}}
{{- $_ := required "serviceTree.layer is required" .Values.serviceTree.layer -}}
{{- if ne $platform .Release.Namespace -}}
{{- fail (printf "serviceTree.platform %q must equal release namespace %q" $platform .Release.Namespace) -}}
{{- end -}}
{{- end -}}

{{/* Every rendered resource name is service-token with exactly one dash. */}}
{{- define "zinc.resourceName" -}}
{{- $service := required "serviceTree.service is required" .root.Values.serviceTree.service | lower -}}
{{- $token := required "resource token is required" .token | lower -}}
{{- if not (regexMatch "^[a-z0-9]+$" $service) -}}
{{- fail (printf "service %q must be dash-less lowercase alphanumeric" $service) -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]+$" $token) -}}
{{- fail (printf "resource token %q must be dash-less lowercase alphanumeric" $token) -}}
{{- end -}}
{{- printf "%s-%s" $service $token -}}
{{- end -}}

{{/* Stable LPSM labels; every serviceTree value is projected through labelPrefix. */}}
{{- define "zinc.labels" -}}
{{- $prefix := include "zinc.labelPrefix" . -}}
helm.sh/chart: {{ include "zinc.chart" . }}
app.kubernetes.io/name: {{ .Values.serviceTree.service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* Matching service-tree annotations; every key uses labelPrefix. */}}
{{- define "zinc.annotations" -}}
{{- $prefix := include "zinc.labelPrefix" . -}}
{{- range $key, $value := .Values.serviceTree }}
{{ printf "%s/%s" $prefix $key }}: {{ $value | quote }}
{{- end }}
{{- end -}}

{{/* One reusable DNS-01 ClusterIssuer definition, called once or twice by issuance class. */}}
{{- define "zinc.clusterIssuer" -}}
{{- $root := .root -}}
{{- $issuer := .issuer -}}
{{- $zones := .dnsZones -}}
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: {{ required "issuer name is required" $issuer.name }}
  labels:
    {{- include "zinc.labels" $root | nindent 4 }}
  annotations:
    {{- include "zinc.annotations" $root | nindent 4 }}
spec:
  acme:
    email: {{ required "issuer email is required" $root.Values.issuer.email | quote }}
    server: {{ required "issuer server is required" $issuer.server | quote }}
    privateKeySecretRef:
      name: {{ required "issuer account Secret name is required" $issuer.accountSecretName }}
    solvers:
      - selector:
          dnsZones:
            {{- toYaml $zones | nindent 12 }}
        dns01:
          cloudflare:
            apiTokenSecretRef:
              name: {{ $root.Values.issuer.cloudflare.apiTokenSecretRef.name }}
              key: {{ $root.Values.issuer.cloudflare.apiTokenSecretRef.key }}
{{- end -}}
