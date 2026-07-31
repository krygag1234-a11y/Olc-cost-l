#!/usr/bin/env bash
# Show how every discovered split/CDN domain was found (target, CNAME, logs,
# brand family, live certificate or crt.sh) instead of presenting a flat list.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-split-provenance-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import pathlib, sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
changed = False

ru_anchor = '    splitAutoGroupsHelp: "Глобальные группы'
ru_pos = text.find(ru_anchor)
if 'splitProvenanceTitle:' not in text and ru_pos >= 0:
    line_end = text.find('\n', ru_pos)
    addition = '''
    splitProvenanceTitle: "Домены и происхождение",
    splitProvenanceHint: "Справа от домена показано, откуда автодетектор его получил.",
    splitProvTarget: "исходная цель",
    splitProvCname: "DNS CNAME",
    splitProvRuntime: "журнал сессии",
    splitProvBrand: "семейство сервиса/CDN",
    splitProvCertificate: "TLS-сертификат",
    splitProvCrtsh: "crt.sh",
    splitProvUnknown: "автодетектор",'''
    text = text[:line_end] + addition + text[line_end:]
    changed = True

en_anchor = '    splitAutoGroupsHelp: "Global groups'
en_pos = text.find(en_anchor)
if 'splitProvenanceTitle: "Domains and provenance"' not in text and en_pos >= 0:
    line_end = text.find('\n', en_pos)
    addition = '''
    splitProvenanceTitle: "Domains and provenance",
    splitProvenanceHint: "Each domain shows how the detector discovered it.",
    splitProvTarget: "source target",
    splitProvCname: "DNS CNAME",
    splitProvRuntime: "session log",
    splitProvBrand: "service/CDN family",
    splitProvCertificate: "TLS certificate",
    splitProvCrtsh: "crt.sh",
    splitProvUnknown: "auto detector",'''
    text = text[:line_end] + addition + text[line_end:]
    changed = True

vars_anchor = '''  const splitAnalysisCidrs = splitAnalysis && Array.isArray(splitAnalysis.cidrs) ? splitAnalysis.cidrs.map(String) : [];'''
vars_add = vars_anchor + '''
  const splitAnalysisProvenance = splitAnalysis && splitAnalysis.domain_provenance && typeof splitAnalysis.domain_provenance === "object"
    ? splitAnalysis.domain_provenance as Record<string, unknown>
    : {};
  const splitDomainWithProvenance = (domain: string, provenance: Record<string, unknown>) => {
    const rawEntries = Array.isArray(provenance[domain]) ? provenance[domain] as Array<Record<string, unknown>> : [];
    const labels = rawEntries.map((entry) => {
      const source = String(entry?.source ?? "unknown");
      const label = source === "target" ? t("splitProvTarget")
        : source === "cname" ? t("splitProvCname")
        : source === "runtime_log" ? t("splitProvRuntime")
        : source === "brand_family" ? t("splitProvBrand")
        : source === "certificate" ? t("splitProvCertificate")
        : source === "crt.sh" ? t("splitProvCrtsh")
        : t("splitProvUnknown");
      const detail = String(entry?.detail ?? "");
      return detail && detail !== domain ? `${label}: ${detail}` : label;
    });
    const unique = Array.from(new Set(labels));
    return unique.length ? `${domain}  ← ${unique.join(", ")}` : domain;
  };'''
if 'const splitDomainWithProvenance' not in text and vars_anchor in text:
    text = text.replace(vars_anchor, vars_add, 1)
    changed = True

analysis_anchor = '''<LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{splitAnalysisDomains.slice(0, 80).join("\\n") || t("empty")}</LogScrollPre>'''
analysis_add = '''<LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2" title={t("splitProvenanceHint")}>{splitAnalysisDomains.slice(0, 80).map((domain) => splitDomainWithProvenance(domain, splitAnalysisProvenance)).join("\\n") || t("empty")}</LogScrollPre>'''
if 'splitDomainWithProvenance(domain, splitAnalysisProvenance)' not in text and analysis_anchor in text:
    text = text.replace(analysis_anchor, analysis_add, 1)
    changed = True

group_anchor = '''                        const cidrs = Array.isArray(g.selected_cidrs) ? g.selected_cidrs.map(String) : Array.isArray(g.cidrs) ? g.cidrs.map(String) : [];
                        const open = Boolean(splitExpanded[id]);'''
group_add = '''                        const cidrs = Array.isArray(g.selected_cidrs) ? g.selected_cidrs.map(String) : Array.isArray(g.cidrs) ? g.cidrs.map(String) : [];
                        const provenance = g.domain_provenance && typeof g.domain_provenance === "object" ? g.domain_provenance as Record<string, unknown> : {};
                        const domainLines = domains.map((domain) => splitDomainWithProvenance(domain, provenance));
                        const open = Boolean(splitExpanded[id]);'''
if 'const domainLines = domains.map' not in text and group_anchor in text:
    text = text.replace(group_anchor, group_add, 1)
    changed = True

list_anchor = '''<LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{domains.join("\\n") || t("empty")}</LogScrollPre>'''
list_add = '''<div>
                                  <div className="mb-1 text-muted-foreground" title={t("splitProvenanceHint")}>{t("splitProvenanceTitle")}</div>
                                  <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{domainLines.join("\\n") || t("empty")}</LogScrollPre>
                                </div>'''
if 'domainLines.join("\\n")' not in text and list_anchor in text:
    text = text.replace(list_anchor, list_add, 1)
    changed = True

required = ['splitProvenanceTitle:', 'const splitDomainWithProvenance', 'const domainLines = domains.map', 'domainLines.join("\\n")']
missing = [marker for marker in required if marker not in text]
if missing:
    raise SystemExit("[patch-split-provenance-ui] missing anchors/results: " + ", ".join(missing))

if changed:
    path.write_text(text)
    print("[patch-split-provenance-ui] OK: provenance labels added")
else:
    print("[patch-split-provenance-ui] no changes (idempotent)")
PY
