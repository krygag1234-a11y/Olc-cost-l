#!/usr/bin/env bash
# Phase 2A Step 2: Collapse discovery.groups by default, add summary

set -e
TARGET="${1:-src/main.tsx}"

if ! [ -f "$TARGET" ]; then
  echo "[split-2a-step2] target not found: $TARGET" >&2
  exit 1
fi

# Idempotency: check if already patched
if grep -q "splitAutoGroupsCollapsed" "$TARGET" 2>/dev/null; then
  echo "[split-2a-step2] already applied" >&2
  exit 0
fi

python3 - "$TARGET" <<'PYSCRIPT'
import sys, re

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    t = f.read()

# Anchor 1: Add useState for splitAutoGroupsCollapsed after splitExpanded
anchor_state = "const [splitExpanded, setSplitExpanded] = useState<Record<string, boolean>>({});"
if anchor_state not in t:
    print("[split-2a-step2] anchor not found: splitExpanded useState", file=sys.stderr)
    sys.exit(1)

new_state = '''const [splitExpanded, setSplitExpanded] = useState<Record<string, boolean>>({});
  const [splitAutoGroupsCollapsed, setSplitAutoGroupsCollapsed] = useState(true);'''

t = t.replace(anchor_state, new_state)

# Anchor 2: Transform "Автоматически найдено" section into collapsible with summary
old_section_start = '''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <div>
                    <div className="font-medium">{t("splitAutoGroupsTitle")}</div>
                    <p className="text-xs text-muted-foreground">{t("splitAutoGroupsHelp")}</p>
                  </div>'''

new_section_start = '''                <section className="rounded-md border border-border bg-muted/20 p-3 space-y-2">
                  <button
                    type="button"
                    className="flex w-full items-center justify-between text-left"
                    onClick={() => setSplitAutoGroupsCollapsed(v => !v)}
                  >
                    <div>
                      <div className="font-medium">{t("splitAutoGroupsTitle")}</div>
                      <p className="text-xs text-muted-foreground">
                        {splitAutoGroupsCollapsed ? (
                          `${splitGroups.length} ${splitGroups.length === 1 ? 'группа' : splitGroups.length < 5 ? 'группы' : 'групп'}, ${
                            splitGroups.reduce((sum, g) => {
                              const domains = Array.isArray(g.selected_domains) ? g.selected_domains : Array.isArray(g.domains) ? g.domains : [];
                              return sum + domains.length;
                            }, 0)
                          } доменов`
                        ) : (
                          t("splitAutoGroupsHelp")
                        )}
                      </p>
                    </div>
                    <span className="text-muted-foreground">{splitAutoGroupsCollapsed ? '▸' : '▾'}</span>
                  </button>'''

if old_section_start not in t:
    print("[split-2a-step2] anchor not found: splitAutoGroupsTitle section", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_section_start, new_section_start)

# Anchor 3: Wrap content in conditional based on splitAutoGroupsCollapsed
old_content = '''                  {splitGroups.length === 0 ? (
                    <p className="text-xs text-muted-foreground">{t("splitNoGroups")}</p>
                  ) : (
                    <div className="space-y-2">
                      {splitGroups.map((g) => {'''

new_content = '''                  {!splitAutoGroupsCollapsed && (
                    <>
                      {splitGroups.length === 0 ? (
                        <p className="text-xs text-muted-foreground">{t("splitNoGroups")}</p>
                      ) : (
                        <div className="space-y-2">
                          {splitGroups.map((g) => {'''

if old_content not in t:
    print("[split-2a-step2] anchor not found: splitGroups content", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_content, new_content)

# Anchor 4: Close the conditional wrapper at the end of groups
old_close = '''                      })}
                    </div>
                  )}
                </section>'''

new_close = '''                          })}
                        </div>
                      )}
                    </>
                  )}
                </section>'''

if old_close not in t:
    print("[split-2a-step2] anchor not found: section close", file=sys.stderr)
    sys.exit(1)

t = t.replace(old_close, new_close)

with open(path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(t)

print("[split-2a-step2] collapse discovery.groups by default: ok", file=sys.stderr)
PYSCRIPT
