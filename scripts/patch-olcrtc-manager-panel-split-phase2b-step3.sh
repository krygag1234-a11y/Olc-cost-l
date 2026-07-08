#!/usr/bin/env bash
# Phase 2B Step 3: Add collapsible for custom_direct_domains + improve UX of all collapsible buttons

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2b-step3] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency check
if grep -q "customDirectExpanded" "$TARGET" 2>/dev/null; then
  echo "[split-2b-step3] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Part 1: Add useState for custom_direct_domains collapsible
# Anchor: after blockedTorExpanded useState
anchor_state = 'const [blockedTorExpanded, setBlockedTorExpanded] = usePersistedOpen("olc-split-blocked-tor-v1");'
if anchor_state not in t:
    print("[split-2b-step3] anchor not found: blockedTorExpanded useState", file=sys.stderr)
    sys.exit(1)

new_state = '''const [blockedTorExpanded, setBlockedTorExpanded] = usePersistedOpen("olc-split-blocked-tor-v1");
  const [customDirectExpanded, setCustomDirectExpanded] = usePersistedOpen("olc-split-custom-direct-v1");'''

t = t.replace(anchor_state, new_state, 1)

# Part 2: Improve UX of all existing collapsible buttons (4 buttons)
# Replace minimal button style with enhanced one (border, hover, padding)
old_button_class = 'className="flex w-full items-center justify-between text-left"'
new_button_class = 'className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"'

# This will replace ALL occurrences (all 4 existing collapsible buttons)
t = t.replace(old_button_class, new_button_class)

# Part 3: Make custom_direct_domains collapsible
# Find the label + list structure and replace with collapsible button + conditional rendering
old_custom_direct = '''                  <div className="space-y-2">
                    <div className="text-xs font-medium text-muted-foreground">{t("splitCustomDirect")}</div>
                    <div className="space-y-1 max-h-[200px] overflow-y-auto">
                      {String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => ('''

new_custom_direct = '''                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setCustomDirectExpanded(v => !v)}
                    >
                      <div className="text-xs font-medium text-muted-foreground">
                        {t("splitCustomDirect")}
                        {!customDirectExpanded && (
                          <span className="ml-2 text-xs text-muted-foreground/70">
                            ({String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).length} элементов)
                          </span>
                        )}
                      </div>
                      <span className="text-muted-foreground text-sm">{customDirectExpanded ? '▾' : '▸'}</span>
                    </button>
                    {customDirectExpanded && (
                      <>
                        <div className="space-y-1 max-h-[120px] overflow-y-auto">
                          {String(settings.custom_direct_domains ?? "").split('\\n').filter(s => s.trim()).map((domain, idx) => ('''

if old_custom_direct not in t:
    print("[split-2b-step3] anchor not found: custom_direct_domains label", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_custom_direct, new_custom_direct, 1)

# Part 4: Close the conditional rendering for custom_direct_domains
# Find the end of "Добавить" button with the specific placeholder for custom_direct
old_add_button_close = '''                        }}
                      >
                        Добавить
                      </button>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setPanelHostsExpanded(v => !v)}'''

new_add_button_close = '''                        }}
                      >
                        Добавить
                      </button>
                    </div>
                      </>
                    )}
                  </div>
                  <div className="space-y-2">
                    <button
                      type="button"
                      className="flex w-full items-center justify-between text-left rounded-md border border-border p-2 hover:bg-muted/50 transition-colors"
                      onClick={() => setPanelHostsExpanded(v => !v)}'''

if old_add_button_close not in t:
    print("[split-2b-step3] anchor not found: custom_direct Добавить button close", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_add_button_close, new_add_button_close, 1)

print("[split-2b-step3] 5 collapsible lists with improved UX: ok", file=sys.stderr)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)
PYSCRIPT
