#!/usr/bin/env bash
# Phase 2A Step 1: Transform custom_direct_domains textarea → card-based list

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2a-step1] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency: check if already patched
if grep -q "newCustomDirectDomain" "$TARGET" 2>/dev/null; then
  echo "[split-2a-step1] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Anchor 1: Add useState for newCustomDirectDomain after splitApplyMenuOpen
anchor_state = "const [splitApplyMenuOpen, setSplitApplyMenuOpen] = useState(false);"
if anchor_state not in t:
    print("[split-2a-step1] anchor not found: splitApplyMenuOpen useState", file=sys.stderr)
    sys.exit(1)

new_state = '''const [splitApplyMenuOpen, setSplitApplyMenuOpen] = useState(false);
  const [newCustomDirectDomain, setNewCustomDirectDomain] = useState("");'''

t = t.replace(anchor_state, new_state)

# Anchor 2: Replace custom_direct_domains textarea with card-based list
# Find the label with textarea for custom_direct_domains
old_ui = '''                  <label className="grid gap-1 text-muted-foreground">
                    {t("splitCustomDirect")}
                    <textarea
                      className="min-h-[90px] rounded-md border border-border bg-background p-2 font-mono text-xs"
                      placeholder="vk.com&#10;userapi.com&#10;87.240.128.0/18"
                      value={String(settings.custom_direct_domains ?? "")}
                      onChange={(e) => setStr("custom_direct_domains", e.target.value)}
                    />
                  </label>'''

new_ui = '''                  <div className="space-y-2">
                    <div className="text-xs font-medium text-muted-foreground">{t("splitCustomDirect")}</div>
                    <div className="space-y-1 max-h-[200px] overflow-y-auto">
                      {String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => (
                        <div key={idx} className="flex items-center justify-between gap-2 rounded border border-border bg-background px-2 py-1.5">
                          <span className="font-mono text-xs truncate">{domain.trim()}</span>
                          <button
                            type="button"
                            className="shrink-0 text-xs text-red-400 hover:text-red-300"
                            onClick={() => {
                              const domains = String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                              const updated = domains.filter((d, i) => i !== idx);
                              setStr("custom_direct_domains", updated.join('\\n'));
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
                        placeholder="vk.com, 87.240.128.0/18"
                        value={newCustomDirectDomain}
                        onChange={(e) => setNewCustomDirectDomain(e.target.value)}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            const trimmed = newCustomDirectDomain.trim();
                            if (!trimmed) return;
                            const domains = String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                            if (domains.includes(trimmed)) {
                              setNewCustomDirectDomain("");
                              return;
                            }
                            const updated = [...domains, trimmed];
                            setStr("custom_direct_domains", updated.join('\\n'));
                            setNewCustomDirectDomain("");
                          }
                        }}
                      />
                      <button
                        type="button"
                        className="rounded border border-primary px-3 py-1 text-xs text-primary hover:bg-primary/10"
                        onClick={() => {
                          const trimmed = newCustomDirectDomain.trim();
                          if (!trimmed) return;
                          const domains = String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map(s => s.trim());
                          if (domains.includes(trimmed)) {
                            setNewCustomDirectDomain("");
                            return;
                          }
                          const updated = [...domains, trimmed];
                          setStr("custom_direct_domains", updated.join('\\n'));
                          setNewCustomDirectDomain("");
                        }}
                      >
                        Добавить
                      </button>
                    </div>
                  </div>'''

if old_ui not in t:
    print("[split-2a-step1] anchor not found: custom_direct_domains textarea", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_ui, new_ui)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)

print("[split-2a-step1] custom_direct_domains: textarea → card-based list: ok", file=sys.stderr)
PYSCRIPT
