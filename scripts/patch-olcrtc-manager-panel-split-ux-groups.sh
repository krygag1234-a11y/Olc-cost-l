#!/usr/bin/env bash
# Make Split analysis actions explicit and organize discovered targets into
# expandable service/domain families with independently expandable subgroups.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-split-ux-groups] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
changed = False

translations = {
    '    splitApplyDefault: "Добавить",': '''    splitApplyDefault: "Добавить в авто-группу Direct",
    splitApplyDestination: "Куда будет добавлено",
    splitApplySelectedDirect: "Авто-группа Split → direct: сайт, найденные CDN и IP/CIDR",
    splitApplySelectedManual: "Ручные direct-исключения: домены/IP/CIDR появятся в верхнем списке",
    splitApplySelectedTor: "Всегда через Tor: найденные домены будут принудительно отправлены в Tor",
    splitApplySelectedBlocked: "RU через VPS/Zapret: домены попадут в список заблокированных RU-сайтов",
    splitFamilyGroups: "подгрупп",''',
    '    splitApplyDefault: "Add",': '''    splitApplyDefault: "Add to automatic Direct group",
    splitApplyDestination: "Destination",
    splitApplySelectedDirect: "Split automatic group → direct: site, discovered CDN and IP/CIDR",
    splitApplySelectedManual: "Manual direct exceptions: domains/IP/CIDR appear in the top list",
    splitApplySelectedTor: "Always through Tor: discovered domains are forced through Tor",
    splitApplySelectedBlocked: "RU through VPS/Zapret: domains enter the blocked RU list",
    splitFamilyGroups: "subgroups",''',
}
for anchor, replacement in translations.items():
    if replacement.splitlines()[1].strip() not in text and anchor in text:
        text = text.replace(anchor, replacement, 1)
        changed = True

state_anchor = '  const [splitApplyMenuOpen, setSplitApplyMenuOpen] = useState(false);'
state_add = state_anchor + '\n  const [splitApplyTarget, setSplitApplyTarget] = useState("direct");'
if 'const [splitApplyTarget,' not in text and state_anchor in text:
    text = text.replace(state_anchor, state_add, 1)
    changed = True

groups_anchor = '  const splitGroups = Array.isArray(splitDiscovery.groups) ? splitDiscovery.groups : [];'
groups_add = groups_anchor + r'''
  const splitFamilies = Array.from(splitGroups.reduce((families, group) => {
    const target = String(group.target ?? group.label ?? "other").toLowerCase();
    const targetParts = target.split(".").filter(Boolean);
    const fallbackBase = targetParts.length > 1 ? targetParts.slice(-2).join(".") : target;
    const vkFamily = /(^|\.)(vk\.com|vk\.ru|vkvideo\.ru|userapi\.com|vkuseraudio\.net|vkuservideo\.net|vkuser\.net|mycdn\.me)$/.test(target);
    const familyId = String(group.family_id ?? (vkFamily ? "brand:vk" : `domain:${fallbackBase}`));
    const familyLabel = String(group.family_label ?? (vkFamily ? "VK" : fallbackBase));
    const current = families.get(familyId) ?? { id: familyId, label: familyLabel, groups: [] as Array<Record<string, unknown>> };
    current.groups.push(group);
    families.set(familyId, current);
    return families;
  }, new Map<string, { id: string; label: string; groups: Array<Record<string, unknown>> }>()).values());
  const splitApplyOptions: Record<string, { label: string; hint: string }> = {
    direct: { label: t("splitApplyDefault"), hint: t("splitApplySelectedDirect") },
    custom_direct: { label: t("splitApplyManualDirect"), hint: t("splitApplySelectedManual") },
    force_tor: { label: t("splitApplyForceTor"), hint: t("splitApplySelectedTor") },
    blocked_tor: { label: t("splitApplyBlockedTor"), hint: t("splitApplySelectedBlocked") },
  };
  const splitApplySelection = splitApplyOptions[splitApplyTarget] ?? splitApplyOptions.direct;'''
if 'const splitFamilies =' not in text and groups_anchor in text:
    text = text.replace(groups_anchor, groups_add, 1)
    changed = True

old_apply = '''                      <div className="relative inline-flex">
                        <button type="button" className="rounded-l border border-primary px-2 py-1 text-xs text-primary" disabled={saving} onClick={() => void splitApplyAnalysis("direct")}>
                          {t("splitApplyDefault")}
                        </button>
                        <button type="button" className="rounded-r border border-l-0 border-primary px-2 py-1 text-xs text-primary" disabled={saving} onClick={() => setSplitApplyMenuOpen((v) => !v)} aria-label={t("splitApplyChoose")}>
                          ▾
                        </button>
                        {splitApplyMenuOpen && (
                          <div className="absolute left-0 top-8 z-20 w-80 rounded border border-border bg-background p-1 shadow-lg">
                            <button type="button" className="block w-full rounded px-2 py-1 text-left text-xs hover:bg-muted" onClick={() => void splitApplyAnalysis("direct")}>
                              {t("splitApplyDirect")}
                            </button>
                            <button type="button" className="block w-full rounded px-2 py-1 text-left text-xs hover:bg-muted" onClick={() => void splitApplyAnalysis("custom_direct")}>
                              {t("splitApplyManualDirect")}
                            </button>
                            <button type="button" className="block w-full rounded px-2 py-1 text-left text-xs hover:bg-muted" onClick={() => void splitApplyAnalysis("force_tor")}>
                              {t("splitApplyForceTor")}
                            </button>
                            <button type="button" className="block w-full rounded px-2 py-1 text-left text-xs hover:bg-muted" onClick={() => void splitApplyAnalysis("blocked_tor")}>
                              {t("splitApplyBlockedTor")}
                            </button>
                          </div>
                        )}
                      </div>'''
new_apply = '''                      <div className="space-y-1">
                        <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{t("splitApplyDestination")}</div>
                        <div className="relative inline-flex max-w-full">
                          <button type="button" className="rounded-l border border-primary px-3 py-1.5 text-left text-xs text-primary hover:bg-primary/10" disabled={saving} onClick={() => void splitApplyAnalysis(splitApplyTarget)}>
                            {splitApplySelection.label}
                          </button>
                          <button type="button" className="rounded-r border border-l-0 border-primary px-2 py-1 text-xs text-primary hover:bg-primary/10" disabled={saving} onClick={() => setSplitApplyMenuOpen((v) => !v)} aria-label={t("splitApplyChoose")}>
                            ▾
                          </button>
                          {splitApplyMenuOpen && (
                            <div className="absolute left-0 top-9 z-20 w-96 max-w-[80vw] rounded border border-border bg-background p-1 shadow-lg">
                              {Object.entries(splitApplyOptions).map(([key, option]) => (
                                <button key={key} type="button" className={`block w-full rounded px-2 py-2 text-left text-xs hover:bg-muted ${splitApplyTarget === key ? "bg-primary/10 text-primary" : ""}`} onClick={() => { setSplitApplyTarget(key); setSplitApplyMenuOpen(false); }}>
                                  <span className="block font-medium">{option.label}</span>
                                  <span className="block pt-0.5 text-[10px] text-muted-foreground">{option.hint}</span>
                                </button>
                              ))}
                            </div>
                          )}
                        </div>
                        <p className="text-[10px] text-muted-foreground">{splitApplySelection.hint}</p>
                      </div>'''
if 'splitApplySelection.label' not in text and old_apply in text:
    text = text.replace(old_apply, new_apply, 1)
    changed = True

section_re = re.compile(r'''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">\n                  <button.*?setSplitAutoGroupsCollapsed\(v => !v\).*?\n                </section>\n\n                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">\n                  <div className="font-medium">\{t\("splitAdvancedTitle"\)\}</div>''', re.S)
new_section = r'''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between text-left"
                    onClick={() => setSplitAutoGroupsCollapsed(v => !v)}
                  >
                    <div>
                      <div className="font-medium">{t("splitAutoGroupsTitle")}</div>
                      <p className="text-xs text-muted-foreground">
                        {splitAutoGroupsCollapsed
                          ? `${splitFamilies.length} семейств · ${splitGroups.length} ${t("splitFamilyGroups")} · ${splitGroups.reduce((sum, g) => sum + (Array.isArray(g.selected_domains) ? g.selected_domains.length : Array.isArray(g.domains) ? g.domains.length : 0), 0)} доменов`
                          : t("splitAutoGroupsHelp")}
                      </p>
                    </div>
                    <span className="text-muted-foreground">{splitAutoGroupsCollapsed ? '▸' : '▾'}</span>
                  </button>
                  {!splitAutoGroupsCollapsed && (
                    splitFamilies.length === 0 ? (
                      <p className="text-xs text-muted-foreground">{t("splitNoGroups")}</p>
                    ) : (
                      <div className="space-y-2">
                        {splitFamilies.map((family) => {
                          const familyKey = `family:${family.id}`;
                          const familyOpen = Boolean(splitExpanded[familyKey]);
                          const familyDomains = family.groups.reduce((sum, g) => sum + (Array.isArray(g.selected_domains) ? g.selected_domains.length : Array.isArray(g.domains) ? g.domains.length : 0), 0);
                          const familyCidrs = family.groups.reduce((sum, g) => sum + (Array.isArray(g.selected_cidrs) ? g.selected_cidrs.length : Array.isArray(g.cidrs) ? g.cidrs.length : 0), 0);
                          return (
                            <div key={family.id} className="rounded border border-border bg-background/70 p-2 text-xs">
                              <button type="button" className="flex w-full items-center justify-between gap-2 text-left" onClick={() => setSplitExpanded((s) => ({ ...s, [familyKey]: !familyOpen }))}>
                                <span className="font-semibold">{familyOpen ? '▾' : '▸'} {family.label}</span>
                                <span className="text-muted-foreground">{family.groups.length} {t("splitFamilyGroups")} · {familyDomains} domains · {familyCidrs} cidr</span>
                              </button>
                              {familyOpen && (
                                <div className="mt-2 space-y-2 border-l border-border pl-2">
                                  {family.groups.map((g) => {
                                    const id = String(g.id ?? g.target ?? g.label ?? Math.random());
                                    const domains = Array.isArray(g.selected_domains) ? g.selected_domains.map(String) : Array.isArray(g.domains) ? g.domains.map(String) : [];
                                    const cidrs = Array.isArray(g.selected_cidrs) ? g.selected_cidrs.map(String) : Array.isArray(g.cidrs) ? g.cidrs.map(String) : [];
                                    const provenance = g.domain_provenance && typeof g.domain_provenance === "object" ? g.domain_provenance as Record<string, unknown> : {};
                                    const domainLines = domains.map((domain) => splitDomainWithProvenance(domain, provenance));
                                    const open = Boolean(splitExpanded[id]);
                                    return (
                                      <div key={id} className="rounded border border-border bg-background p-2">
                                        <button type="button" className="flex w-full items-center justify-between gap-2 text-left" onClick={() => setSplitExpanded((s) => ({ ...s, [id]: !open }))}>
                                          <span className="font-medium">{open ? '▾' : '▸'} {String(g.label ?? g.target ?? id)}</span>
                                          <span className="text-muted-foreground">{String(g.source ?? "auto")} · {domains.length} domains · {cidrs.length} cidr</span>
                                        </button>
                                        {open && (
                                          <div className="mt-2 grid gap-2 md:grid-cols-2">
                                            <div>
                                              <div className="mb-1 text-muted-foreground" title={t("splitProvenanceHint")}>{t("splitProvenanceTitle")}</div>
                                              <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{domainLines.join("\n") || t("empty")}</LogScrollPre>
                                            </div>
                                            <LogScrollPre className="max-h-[120px] overflow-y-auto rounded bg-muted p-2">{cidrs.join("\n") || t("empty")}</LogScrollPre>
                                          </div>
                                        )}
                                      </div>
                                    );
                                  })}
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )
                  )}
                </section>

                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div className="font-medium">{t("splitAdvancedTitle")}</div>'''
if 'family.groups.map((g)' not in text:
    text, count = section_re.subn(new_section, text, count=1)
    if count:
        changed = True

required = [
    'const [splitApplyTarget,', 'const splitFamilies =', 'splitApplySelection.label',
    'family.groups.map((g)', 'data-ui="split-apply-compact"',
]
missing = [marker for marker in required if marker not in text]
if missing:
    raise SystemExit("[patch-split-ux-groups] missing results: " + ", ".join(missing))

if changed:
    path.write_text(text)
    print("[patch-split-ux-groups] explicit destination + family hierarchy: ok")
else:
    print("[patch-split-ux-groups] no changes (idempotent)")
PY
