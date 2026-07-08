#!/usr/bin/env bash
# Phase 2B Step 2: Make 4 lists collapsible with persisted state + reduce height

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2b-step2] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency: check if already patched
if grep -q "panelHostsExpanded" "$TARGET" 2>/dev/null; then
  echo "[split-2b-step2] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Anchor 1: Add 4 useState with usePersistedOpen after newBlockedTorDomain
anchor_state = 'const [newBlockedTorDomain, setNewBlockedTorDomain] = useState("");'
if anchor_state not in t:
    print("[split-2b-step2] anchor not found: newBlockedTorDomain useState", file=sys.stderr)
    sys.exit(1)

new_state = '''const [newBlockedTorDomain, setNewBlockedTorDomain] = useState("");
  const [panelHostsExpanded, setPanelHostsExpanded] = usePersistedOpen("olc-split-panel-hosts-v1");
  const [panelCidrsExpanded, setPanelCidrsExpanded] = usePersistedOpen("olc-split-panel-cidrs-v1");
  const [forceTorExpanded, setForceTorExpanded] = usePersistedOpen("olc-split-force-tor-v1");
  const [blockedTorExpanded, setBlockedTorExpanded] = usePersistedOpen("olc-split-blocked-tor-v1");'''

t = t.replace(anchor_state, new_state, 1)

# Anchor 2: Replace panel_hosts with collapsible version (height 200→120)
old_panel_hosts = '''                  <div className="space-y-2">
                    <div className="text-xs font-medium text-muted-foreground">{t("splitPanelHosts")}</div>
                    <div className="space-y-1 max-h-[200px] overflow-y-auto">
                      {String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map((host, idx) => (
                        <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                          <span className="font-mono text-xs truncate">{host.trim()}</span>
                          <button
                            type="button"
                            className="shrink-0 text-xs text-red-400 hover:text-red-300"
                            onClick={() => {
                              const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              const updated = hosts.filter((h, i) => i !== idx);
                              setStr("panel_hosts", updated.join('\\n'));
                            }}
                            title="Удалить"
                          >
                            ✕
                          </button>
                        </div>
                      ))}
                    </div>
                    <div className="flex gap-2">
                      <input
                        className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                        placeholder="example.com"
                        value={newPanelHost}
                        onChange={(e) => setNewPanelHost(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            const trimmed = newPanelHost.trim();
                            if (!trimmed) return;
                            const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                            if (hosts.includes(trimmed)) {
                              setNewPanelHost("");
                              return;
                            }
                            const updated = [...hosts, trimmed];
                            setStr("panel_hosts", updated.join('\\n'));
                            setNewPanelHost("");
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                        onClick={() => {
                          const trimmed = newPanelHost.trim();
                          if (!trimmed) return;
                          const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                          if (hosts.includes(trimmed)) {
                            setNewPanelHost("");
                            return;
                          }
                          const updated = [...hosts, trimmed];
                          setStr("panel_hosts", updated.join('\\n'));
                          setNewPanelHost("");
                        }}
                      >
                        Добавить
                      </button>
                    </div>
                  </div>'''

new_panel_hosts = '''                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left"
                      onClick={() => setPanelHostsExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitPanelHosts")}
                        {!panelHostsExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{panelHostsExpanded ? '▾' : '▸'}</span>
                    </button>
                    {panelHostsExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map((host, idx) => (
                            <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                              <span className="font-mono text-xs truncate">{host.trim()}</span>
                              <button
                                type="button"
                                className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                onClick={() => {
                                  const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                  const updated = hosts.filter((h, i) => i !== idx);
                                  setStr("panel_hosts", updated.join('\\n'));
                                }}
                                title="Удалить"
                              >
                                ✕
                              </button>
                            </div>
                          ))}
                        </div>
                        <div className="flex gap-2">
                          <input
                            className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                            placeholder="example.com"
                            value={newPanelHost}
                            onChange={(e) => setNewPanelHost(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.preventDefault();
                                const trimmed = newPanelHost.trim();
                                if (!trimmed) return;
                                const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                if (hosts.includes(trimmed)) {
                                  setNewPanelHost("");
                                  return;
                                }
                                const updated = [...hosts, trimmed];
                                setStr("panel_hosts", updated.join('\\n'));
                                setNewPanelHost("");
                              }
                            }}
                          />
                          <button
                            type="button"
                            className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                            onClick={() => {
                              const trimmed = newPanelHost.trim();
                              if (!trimmed) return;
                              const hosts = String(settings.panel_hosts ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              if (hosts.includes(trimmed)) {
                                setNewPanelHost("");
                                return;
                              }
                              const updated = [...hosts, trimmed];
                              setStr("panel_hosts", updated.join('\\n'));
                              setNewPanelHost("");
                            }}
                          >
                            Добавить
                          </button>
                        </div>
                      </>
                    )}
                  </div>'''

if old_panel_hosts not in t:
    print("[split-2b-step2] anchor not found: panel_hosts", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_panel_hosts, new_panel_hosts, 1)

# Anchor 3: Replace panel_cidrs with collapsible version (height 200→120)
old_panel_cidrs = '''                  <div className="space-y-2">
                    <div className="text-xs font-medium text-muted-foreground">{t("splitPanelCidrs")}</div>
                    <div className="space-y-1 max-h-[200px] overflow-y-auto">
                      {String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map((cidr, idx) => (
                        <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                          <span className="font-mono text-xs truncate">{cidr.trim()}</span>
                          <button
                            type="button"
                            className="shrink-0 text-xs text-red-400 hover:text-red-300"
                            onClick={() => {
                              const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              const updated = cidrs.filter((c, i) => i !== idx);
                              setStr("panel_cidrs", updated.join('\\n'));
                            }}
                            title="Удалить"
                          >
                            ✕
                          </button>
                        </div>
                      ))}
                    </div>
                    <div className="flex gap-2">
                      <input
                        className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                        placeholder="10.0.0.0/8"
                        value={newPanelCidr}
                        onChange={(e) => setNewPanelCidr(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            const trimmed = newPanelCidr.trim();
                            if (!trimmed) return;
                            const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                            if (cidrs.includes(trimmed)) {
                              setNewPanelCidr("");
                              return;
                            }
                            const updated = [...cidrs, trimmed];
                            setStr("panel_cidrs", updated.join('\\n'));
                            setNewPanelCidr("");
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                        onClick={() => {
                          const trimmed = newPanelCidr.trim();
                          if (!trimmed) return;
                          const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                          if (cidrs.includes(trimmed)) {
                            setNewPanelCidr("");
                            return;
                          }
                          const updated = [...cidrs, trimmed];
                          setStr("panel_cidrs", updated.join('\\n'));
                          setNewPanelCidr("");
                        }}
                      >
                        Добавить
                      </button>
                    </div>
                  </div>'''

new_panel_cidrs = '''                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left"
                      onClick={() => setPanelCidrsExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitPanelCidrs")}
                        {!panelCidrsExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{panelCidrsExpanded ? '▾' : '▸'}</span>
                    </button>
                    {panelCidrsExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map((cidr, idx) => (
                            <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                              <span className="font-mono text-xs truncate">{cidr.trim()}</span>
                              <button
                                type="button"
                                className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                onClick={() => {
                                  const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                  const updated = cidrs.filter((c, i) => i !== idx);
                                  setStr("panel_cidrs", updated.join('\\n'));
                                }}
                                title="Удалить"
                              >
                                ✕
                              </button>
                            </div>
                          ))}
                        </div>
                        <div className="flex gap-2">
                          <input
                            className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                            placeholder="10.0.0.0/8"
                            value={newPanelCidr}
                            onChange={(e) => setNewPanelCidr(e.target.value)}
                            onKeyDown={(e) => {
                              if (e.key === 'Enter') {
                                e.preventDefault();
                                const trimmed = newPanelCidr.trim();
                                if (!trimmed) return;
                                const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                if (cidrs.includes(trimmed)) {
                                  setNewPanelCidr("");
                                  return;
                                }
                                const updated = [...cidrs, trimmed];
                                setStr("panel_cidrs", updated.join('\\n'));
                                setNewPanelCidr("");
                              }
                            }}
                          />
                          <button
                            type="button"
                            className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                            onClick={() => {
                              const trimmed = newPanelCidr.trim();
                              if (!trimmed) return;
                              const cidrs = String(settings.panel_cidrs ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              if (cidrs.includes(trimmed)) {
                                setNewPanelCidr("");
                                return;
                              }
                              const updated = [...cidrs, trimmed];
                              setStr("panel_cidrs", updated.join('\\n'));
                              setNewPanelCidr("");
                            }}
                          >
                            Добавить
                          </button>
                        </div>
                      </>
                    )}
                  </div>'''

if old_panel_cidrs not in t:
    print("[split-2b-step2] anchor not found: panel_cidrs", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_panel_cidrs, new_panel_cidrs, 1)

# Anchor 4: Replace force_tor_domains with collapsible version (height 200→120)
# Phase 2B already replaced textarea with card-based list, so search for that structure
old_force_tor = '''                    <div className="space-y-2">
                      <div className="space-y-1 max-h-[200px] overflow-y-auto">
                        {String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => (
                          <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                            <span className="font-mono text-xs truncate">{domain.trim()}</span>
                            <button
                              type="button"
                              className="shrink-0 text-xs text-red-400 hover:text-red-300"
                              onClick={() => {
                                const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                const updated = domains.filter((d, i) => i !== idx);
                                setStr("force_tor_domains", updated.join('\\n'));
                              }}
                              title="Удалить"
                            >
                              ✕
                            </button>
                          </div>
                        ))}
                      </div>
                      <div className="flex gap-2">
                        <input
                          className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                          placeholder="example.com"
                          value={newForceTorDomain}
                          onChange={(e) => setNewForceTorDomain(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') {
                              e.preventDefault();
                              const trimmed = newForceTorDomain.trim();
                              if (!trimmed) return;
                              const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              if (domains.includes(trimmed)) {
                                setNewForceTorDomain("");
                                return;
                              }
                              const updated = [...domains, trimmed];
                              setStr("force_tor_domains", updated.join('\\n'));
                              setNewForceTorDomain("");
                            }
                          }}
                        />
                        <button
                          type="button"
                          className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                          onClick={() => {
                            const trimmed = newForceTorDomain.trim();
                            if (!trimmed) return;
                            const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                            if (domains.includes(trimmed)) {
                              setNewForceTorDomain("");
                              return;
                            }
                            const updated = [...domains, trimmed];
                            setStr("force_tor_domains", updated.join('\\n'));
                            setNewForceTorDomain("");
                          }}
                        >
                          Добавить
                        </button>
                      </div>
                    </div>'''

new_force_tor = '''                    <div className="space-y-2">
                      <button
                        type="button"
                        className="flex w-full items-center justify-between text-left"
                        onClick={() => setForceTorExpanded(v => !v)}
                      >
                        <div className="text-xs font-medium">
                          {!forceTorExpanded && (
                            <span className="text-xs text-muted-foreground/70">
                              ({String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).length} элементов)
                            </span>
                          )}
                        </div>
                        <span className="text-muted-foreground text-sm">{forceTorExpanded ? '▾' : '▸'}</span>
                      </button>
                      {forceTorExpanded && (
                        <>
                          <div className="space-y-1 max-h-[120px] overflow-y-auto">
                            {String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => (
                              <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                                <span className="font-mono text-xs truncate">{domain.trim()}</span>
                                <button
                                  type="button"
                                  className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                  onClick={() => {
                                    const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                    const updated = domains.filter((d, i) => i !== idx);
                                    setStr("force_tor_domains", updated.join('\\n'));
                                  }}
                                  title="Удалить"
                                >
                                  ✕
                                </button>
                              </div>
                            ))}
                          </div>
                          <div className="flex gap-2">
                            <input
                              className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                              placeholder="example.com"
                              value={newForceTorDomain}
                              onChange={(e) => setNewForceTorDomain(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  const trimmed = newForceTorDomain.trim();
                                  if (!trimmed) return;
                                  const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                  if (domains.includes(trimmed)) {
                                    setNewForceTorDomain("");
                                    return;
                                  }
                                  const updated = [...domains, trimmed];
                                  setStr("force_tor_domains", updated.join('\\n'));
                                  setNewForceTorDomain("");
                                }
                              }}
                            />
                            <button
                              type="button"
                              className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                              onClick={() => {
                                const trimmed = newForceTorDomain.trim();
                                if (!trimmed) return;
                                const domains = String(settings.force_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                if (domains.includes(trimmed)) {
                                  setNewForceTorDomain("");
                                  return;
                                }
                                const updated = [...domains, trimmed];
                                setStr("force_tor_domains", updated.join('\\n'));
                                setNewForceTorDomain("");
                              }}
                            >
                              Добавить
                            </button>
                          </div>
                        </>
                      )}
                    </div>'''

if old_force_tor not in t:
    print("[split-2b-step2] anchor not found: force_tor_domains", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_force_tor, new_force_tor, 1)

# Anchor 5: Replace blocked_tor_domains with collapsible version (height 200→120)
# Phase 2B already replaced textarea with card-based list, so search for that structure
old_blocked_tor = '''                    <div className="space-y-2">
                      <div className="space-y-1 max-h-[200px] overflow-y-auto">
                        {String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => (
                          <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                            <span className="font-mono text-xs truncate">{domain.trim()}</span>
                            <button
                              type="button"
                              className="shrink-0 text-xs text-red-400 hover:text-red-300"
                              onClick={() => {
                                const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                const updated = domains.filter((d, i) => i !== idx);
                                setStr("blocked_tor_domains", updated.join('\\n'));
                              }}
                              title="Удалить"
                            >
                              ✕
                            </button>
                          </div>
                        ))}
                      </div>
                      <div className="flex gap-2">
                        <input
                          className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                          placeholder="example.com"
                          value={newBlockedTorDomain}
                          onChange={(e) => setNewBlockedTorDomain(e.target.value)}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter') {
                              e.preventDefault();
                              const trimmed = newBlockedTorDomain.trim();
                              if (!trimmed) return;
                              const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              if (domains.includes(trimmed)) {
                                setNewBlockedTorDomain("");
                                return;
                              }
                              const updated = [...domains, trimmed];
                              setStr("blocked_tor_domains", updated.join('\\n'));
                              setNewBlockedTorDomain("");
                            }
                          }}
                        />
                        <button
                          type="button"
                          className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                          onClick={() => {
                            const trimmed = newBlockedTorDomain.trim();
                            if (!trimmed) return;
                            const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                            if (domains.includes(trimmed)) {
                              setNewBlockedTorDomain("");
                              return;
                            }
                            const updated = [...domains, trimmed];
                            setStr("blocked_tor_domains", updated.join('\\n'));
                            setNewBlockedTorDomain("");
                          }}
                        >
                          Добавить
                        </button>
                      </div>
                    </div>'''

new_blocked_tor = '''                    <div className="space-y-2">
                      <button
                        type="button"
                        className="flex w-full items-center justify-between text-left"
                        onClick={() => setBlockedTorExpanded(v => !v)}
                      >
                        <div className="text-xs font-medium">
                          {!blockedTorExpanded && (
                            <span className="text-xs text-muted-foreground/70">
                              ({String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).length} элементов)
                            </span>
                          )}
                        </div>
                        <span className="text-muted-foreground text-sm">{blockedTorExpanded ? '▾' : '▸'}</span>
                      </button>
                      {blockedTorExpanded && (
                        <>
                          <div className="space-y-1 max-h-[120px] overflow-y-auto">
                            {String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => (
                              <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                                <span className="font-mono text-xs truncate">{domain.trim()}</span>
                                <button
                                  type="button"
                                  className="shrink-0 text-xs text-red-400 hover:text-red-300"
                                  onClick={() => {
                                    const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                    const updated = domains.filter((d, i) => i !== idx);
                                    setStr("blocked_tor_domains", updated.join('\\n'));
                                  }}
                                  title="Удалить"
                                >
                                  ✕
                                </button>
                              </div>
                            ))}
                          </div>
                          <div className="flex gap-2">
                            <input
                              className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs font-mono"
                              placeholder="example.com"
                              value={newBlockedTorDomain}
                              onChange={(e) => setNewBlockedTorDomain(e.target.value)}
                              onKeyDown={(e) => {
                                if (e.key === 'Enter') {
                                  e.preventDefault();
                                  const trimmed = newBlockedTorDomain.trim();
                                  if (!trimmed) return;
                                  const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                  if (domains.includes(trimmed)) {
                                    setNewBlockedTorDomain("");
                                    return;
                                  }
                                  const updated = [...domains, trimmed];
                                  setStr("blocked_tor_domains", updated.join('\\n'));
                                  setNewBlockedTorDomain("");
                                }
                              }}
                            />
                            <button
                              type="button"
                              className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                              onClick={() => {
                                const trimmed = newBlockedTorDomain.trim();
                                if (!trimmed) return;
                                const domains = String(settings.blocked_tor_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                                if (domains.includes(trimmed)) {
                                  setNewBlockedTorDomain("");
                                  return;
                                }
                                const updated = [...domains, trimmed];
                                setStr("blocked_tor_domains", updated.join('\\n'));
                                setNewBlockedTorDomain("");
                              }}
                            >
                              Добавить
                            </button>
                          </div>
                        </>
                      )}
                    </div>'''

if old_blocked_tor not in t:
    print("[split-2b-step2] anchor not found: blocked_tor_domains", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_blocked_tor, new_blocked_tor, 1)

print("[split-2b-step2] 4 collapsible lists with persisted state: ok", file=sys.stderr)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)
PYSCRIPT
