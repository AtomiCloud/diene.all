{{- define "boron.fullname" -}}
{{- .Release.Name -}}
{{- end -}}

{{- /* Boron never installs on hosted (eevee/plusle/minun) or hermetic
(rotom/absol) profiles: ENTEI owns hosted edge functions and hermetic profiles
are tunnel-free. Rendering with such a profile fails closed at template time so
a Garden profile mistake cannot silently deploy a tunnel operator. */ -}}
{{- define "boron.assertProfile" -}}
{{- $profile := .Values.installation.profile -}}
{{- if not (has $profile (list "lapras" "ditto" "registered")) -}}
{{- fail (printf "boron never installs on profile %q: only connected lapras, explicitly inspectable ditto, or registered clusters run Boron (eevee/plusle/minun are ENTEI-owned; rotom/absol are tunnel-free)" $profile) -}}
{{- end -}}
{{- if and (eq $profile "ditto") (not .Values.installation.dittoInspect) -}}
{{- fail "boron on ditto requires installation.dittoInspect=true (explicitly inspectable runs only)" -}}
{{- end -}}
{{- end -}}

{{- define "boron.serviceAccountName" -}}
{{- default (include "boron.fullname" .) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "boron.scraperName" -}}
{{- default (printf "%s-metrics-reader" (include "boron.fullname" .)) .Values.serviceMonitor.scraper.serviceAccountName -}}
{{- end -}}

{{- define "boron.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "boron.selectorLabels" -}}
app.kubernetes.io/name: boron
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "boron.labels" -}}
app.kubernetes.io/name: boron
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
