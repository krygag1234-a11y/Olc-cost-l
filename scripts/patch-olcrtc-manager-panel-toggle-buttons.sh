#!/usr/bin/env bash
# Replace native checkbox controls with adaptive panel toggle buttons.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[toggle-buttons] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_TOGGLE_BUTTONS_UI_V1"
if marker in text:
    print(f"[toggle-buttons] already applied: {path}")
    raise SystemExit(0)

needle = 'type="checkbox"'
original_count = text.count(needle)
if original_count != 32:
    raise SystemExit(f"[toggle-buttons] expected 32 native checkboxes, got {original_count}")

component = r'''/* OLC_TOGGLE_BUTTONS_UI_V1 */
type OlcToggleButtonProps = {
  checked?: boolean;
  disabled?: boolean;
  mixed?: boolean;
  compact?: boolean;
  title?: string;
  className?: string;
  onClick?: (event: React.MouseEvent<HTMLButtonElement>) => void;
  onChange?: (event: { target: { checked: boolean }; currentTarget: { checked: boolean } }) => void;
};

function OlcToggleButton({ checked = false, disabled = false, mixed = false, compact = false, title, className = "", onClick, onChange }: OlcToggleButtonProps) {
  const stateLabel = mixed ? "Часть" : checked ? "Вкл" : "Выкл";
  const stateClass = mixed
    ? "border-amber-400/50 bg-amber-500/15 text-amber-200"
    : checked
      ? "border-emerald-400/50 bg-emerald-500/15 text-emerald-200"
      : "border-border bg-muted/50 text-muted-foreground";
  const sizeClass = compact ? "h-6 min-w-[44px] px-1.5 text-[10px]" : "h-8 min-w-[72px] px-3 text-xs";
  return (
    <button
      type="button"
      role="switch"
      aria-checked={mixed ? "mixed" : checked}
      aria-label={title || stateLabel}
      title={title}
      disabled={disabled}
      className={`inline-flex shrink-0 items-center justify-center rounded-md border font-semibold transition-colors ${sizeClass} ${stateClass} ${disabled ? "cursor-not-allowed opacity-50" : "cursor-pointer hover:brightness-110"} ${className}`}
      onClick={(event) => {
        onClick?.(event);
        if (event.defaultPrevented || disabled) return;
        const next = !checked;
        onChange?.({ target: { checked: next }, currentTarget: { checked: next } });
      }}
    >
      {stateLabel}
    </button>
  );
}

'''
anchor = "function InstanceDefaultsModal("
if text.count(anchor) != 1:
    raise SystemExit(f"[toggle-buttons] insertion anchor count is {text.count(anchor)}")
text = text.replace(anchor, component + anchor, 1)

positions = []
search_from = 0
while True:
    type_pos = text.find(needle, search_from)
    if type_pos < 0:
        break
    start = text.rfind("<input", 0, type_pos)
    end = text.find("/>", type_pos)
    if start < 0 or end < 0:
        raise SystemExit("[toggle-buttons] cannot locate checkbox tag bounds")
    end += 2
    positions.append((start, end))
    search_from = end

compact_count = 0
mixed_count = 0
for start, end in reversed(positions):
    tag = text[start:end]
    compact = any(token in tag for token in (
        "checked={d.enabled !== false}",
        "checked={x.enabled}",
        "checked={allSel}",
        "checked={connInstances.includes",
        "disabled={globalEnabled}",
    ))
    if compact:
        compact_count += 1
    if "el.indeterminate = sel > 0 && !allSel" in tag:
        old_ref = 'ref={(el) => { if (el) el.indeterminate = sel > 0 && !allSel; }}'
        if old_ref not in tag:
            raise SystemExit("[toggle-buttons] indeterminate ref shape changed")
        tag = tag.replace(old_ref, "mixed={sel > 0 && !allSel}", 1)
        mixed_count += 1
    tag = tag.replace(needle, "", 1)
    tag = tag.replace("<input", "<OlcToggleButton compact" if compact else "<OlcToggleButton", 1)
    text = text[:start] + tag + text[end:]

for duplicate in (
    '<span className="text-xs">{globalEnabled ? "ON (глобально)" : enabled ? "On" : "Off"}</span>',
    '<span className={on ? "text-emerald-600 font-medium" : ""}>{on ? "Вкл" : "Выкл"}</span>',
):
    if text.count(duplicate) != 1:
        raise SystemExit(f"[toggle-buttons] duplicate status anchor count is {text.count(duplicate)}")
    text = text.replace(duplicate, "", 1)

if text.count(needle) != 0:
    raise SystemExit("[toggle-buttons] native checkbox remained")
if text.count("<OlcToggleButton") != original_count:
    raise SystemExit(f"[toggle-buttons] expected {original_count} toggle uses, got {text.count('<OlcToggleButton')}")
if compact_count != 13:
    raise SystemExit(f"[toggle-buttons] expected 13 compact toggles, got {compact_count}")
if mixed_count != 1:
    raise SystemExit(f"[toggle-buttons] expected one mixed toggle, got {mixed_count}")

path.write_text(text)
print(f"[toggle-buttons] applied: total={original_count} compact={compact_count} regular={original_count-compact_count} mixed={mixed_count}")
PY