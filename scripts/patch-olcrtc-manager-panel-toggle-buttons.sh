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
marker = "OLC_TOGGLE_BUTTONS_UI_V4"
if marker in text:
    print(f"[toggle-buttons] already applied: {path}")
    raise SystemExit(0)

def neutralize_toggle_contexts(source: str) -> tuple[str, int]:
    # A native checkbox used to make its whole <label> clickable. After replacing
    # it with a real button, keep only the button interactive.
    wrappers = set()
    search_from = 0
    while True:
        pos = source.find("<OlcToggleButton", search_from)
        if pos < 0:
            break
        label_open = source.rfind("<label", 0, pos)
        label_closed = source.rfind("</label>", 0, pos)
        if label_open > label_closed:
            open_end = source.find(">", label_open)
            close_start = source.find("</label>", pos)
            if open_end < 0 or close_start < 0 or source.find("<label", open_end, pos) >= 0:
                raise SystemExit("[toggle-buttons] cannot safely unwrap clickable label")
            wrappers.add((label_open, open_end + 1, close_start, close_start + len("</label>")))
        search_from = pos + 1
    for open_start, open_end, close_start, close_end in sorted(wrappers, reverse=True):
        open_tag = source[open_start:open_end].replace("<label", "<div", 1)
        source = source[:close_start] + "</div>" + source[close_end:]
        source = source[:open_start] + open_tag + source[open_end:]
    source = source.replace("Включить глобальную рандомизацию", "Глобальная рандомизация")
    return source, len(wrappers)

legacy_marker_v1 = "OLC_TOGGLE_BUTTONS_UI_V1"
legacy_marker_v2 = "OLC_TOGGLE_BUTTONS_UI_V2"
legacy_marker_v3 = "OLC_TOGGLE_BUTTONS_UI_V3"
legacy_state = '''  const stateClass = mixed
    ? "border-amber-400/50 bg-amber-500/15 text-amber-200"
    : checked
      ? "border-emerald-400/50 bg-emerald-500/15 text-emerald-200"
      : "border-border bg-muted/50 text-muted-foreground";'''
neutral_state = '''  const stateClass = mixed
    ? "border-border bg-muted text-foreground"
    : checked
      ? "border-border bg-secondary text-secondary-foreground shadow-sm"
      : "border-border/80 bg-background text-muted-foreground";'''
muted_color_state = '''  const stateClass = mixed
    ? "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
    : checked
      ? "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
      : "border-border bg-transparent text-foreground hover:bg-muted";'''
if legacy_marker_v1 in text or legacy_marker_v2 in text or legacy_marker_v3 in text:
    if legacy_marker_v1 in text:
        if text.count(legacy_state) != 1:
            raise SystemExit("[toggle-buttons] legacy state style shape changed")
        text = text.replace(legacy_marker_v1, marker, 1)
        text = text.replace(legacy_state, muted_color_state, 1)
    elif legacy_marker_v3 in text:
        if text.count(neutral_state) != 1:
            raise SystemExit("[toggle-buttons] v3 neutral state style shape changed")
        text = text.replace(legacy_marker_v3, marker, 1)
        text = text.replace(neutral_state, muted_color_state, 1)
    else:
        text = text.replace(legacy_marker_v2, marker, 1)
        if neutral_state in text:
            text = text.replace(neutral_state, muted_color_state, 1)
        elif legacy_state in text:
            text = text.replace(legacy_state, muted_color_state, 1)
        else:
            raise SystemExit("[toggle-buttons] v2 state style shape changed")
    text = text.replace(
        'cursor-pointer hover:bg-accent hover:text-accent-foreground',
        'cursor-pointer',
        1,
    )
    text = text.replace('cursor-pointer hover:brightness-110', 'cursor-pointer', 1)
    text = text.replace(
        '      onClick={(event) => {\n        onClick?.(event);',
        '      onClick={(event) => {\n        event.stopPropagation();\n        onClick?.(event);',
        1,
    )
    text, wrapper_count = neutralize_toggle_contexts(text)
    path.write_text(text)
    print(f"[toggle-buttons] upgraded muted semantic colors and click targets: wrappers={wrapper_count} {path}")
    raise SystemExit(0)

needle = 'type="checkbox"'
original_count = text.count(needle)
if original_count != 32:
    raise SystemExit(f"[toggle-buttons] expected 32 native checkboxes, got {original_count}")

component = r'''/* OLC_TOGGLE_BUTTONS_UI_V4 */
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
    ? "border-amber-500/40 bg-amber-500/10 text-amber-600 hover:bg-amber-500/20"
    : checked
      ? "border-green-500/40 bg-green-500/10 text-green-600 hover:bg-green-500/20"
      : "border-border bg-transparent text-foreground hover:bg-muted";
  const sizeClass = compact ? "h-6 min-w-[44px] px-1.5 text-[10px]" : "h-8 min-w-[72px] px-3 text-xs";
  return (
    <button
      type="button"
      role="switch"
      aria-checked={mixed ? "mixed" : checked}
      aria-label={title || stateLabel}
      title={title}
      disabled={disabled}
      className={`inline-flex shrink-0 items-center justify-center rounded-md border font-semibold transition-colors ${sizeClass} ${stateClass} ${disabled ? "cursor-not-allowed opacity-50" : "cursor-pointer"} ${className}`}
      onClick={(event) => {
        event.stopPropagation();
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

text, wrapper_count = neutralize_toggle_contexts(text)

if text.count(needle) != 0:
    raise SystemExit("[toggle-buttons] native checkbox remained")
if text.count("<OlcToggleButton") != original_count:
    raise SystemExit(f"[toggle-buttons] expected {original_count} toggle uses, got {text.count('<OlcToggleButton')}")
if compact_count != 13:
    raise SystemExit(f"[toggle-buttons] expected 13 compact toggles, got {compact_count}")
if mixed_count != 1:
    raise SystemExit(f"[toggle-buttons] expected one mixed toggle, got {mixed_count}")

path.write_text(text)
print(f"[toggle-buttons] applied: total={original_count} compact={compact_count} regular={original_count-compact_count} mixed={mixed_count} wrappers={wrapper_count}")
PY
