#!/usr/bin/env bash
set -euo pipefail

tsx=${1:?usage: $0 <main.tsx>}
[[ -f "$tsx" ]] || { echo "[patch-confirm-dialogs] missing $tsx" >&2; exit 1; }

python3 - "$tsx" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

helper = r'''type OlcConfirmOptions = {
  title?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
};

function olcConfirm(message: string, options: OlcConfirmOptions = {}): Promise<boolean> {
  return new Promise((resolve) => {
    const overlay = document.createElement("div");
    overlay.className = "fixed inset-0 z-[100] grid place-items-center bg-black/70 p-4";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");

    const panel = document.createElement("div");
    panel.className = "w-full max-w-lg rounded-lg border border-border bg-card p-4 shadow-2xl";

    const title = document.createElement("div");
    title.className = "text-base font-semibold text-foreground";
    title.textContent = options.title || "Подтвердите действие";

    const body = document.createElement("p");
    body.className = "mt-2 whitespace-pre-line text-sm leading-relaxed text-muted-foreground";
    body.textContent = String(message || "");

    const actions = document.createElement("div");
    actions.className = "mt-4 flex justify-end gap-2";

    const cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "rounded-md border border-border px-3 py-1.5 text-sm hover:bg-muted";
    cancel.textContent = options.cancelLabel || "Отмена";

    const confirm = document.createElement("button");
    confirm.type = "button";
    const inferredDanger = /удал|уничтож|переустанов|отключ|uninstall|delete/i.test(String(message || ""));
    const danger = options.danger ?? inferredDanger;
    confirm.className = danger
      ? "rounded-md border border-red-500/60 bg-red-500/15 px-3 py-1.5 text-sm text-red-300 hover:bg-red-500/25"
      : "rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1.5 text-sm text-amber-300 hover:bg-amber-500/25";
    confirm.textContent = options.confirmLabel || "Продолжить";

    const previousOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
    let finished = false;
    const finish = (accepted: boolean) => {
      if (finished) return;
      finished = true;
      document.removeEventListener("keydown", onKeyDown);
      document.documentElement.style.overflow = previousOverflow;
      overlay.remove();
      resolve(accepted);
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") finish(false);
      if (event.key === "Enter") finish(true);
    };
    cancel.addEventListener("click", () => finish(false));
    confirm.addEventListener("click", () => finish(true));
    overlay.addEventListener("mousedown", (event) => {
      if (event.target === overlay) finish(false);
    });
    document.addEventListener("keydown", onKeyDown);

    actions.append(cancel, confirm);
    panel.append(title, body, actions);
    overlay.append(panel);
    document.body.append(overlay);
    window.requestAnimationFrame(() => confirm.focus());
  });
}

'''

if 'function olcConfirm(message: string' not in text:
    anchor = 'function Modal({'
    if anchor not in text:
        raise SystemExit('[patch-confirm-dialogs] Modal anchor not found')
    text = text.replace(anchor, helper + anchor, 1)

replaced = text.count('window.confirm(')
text = text.replace('window.confirm(', 'await olcConfirm(')
if 'window.confirm' in text:
    raise SystemExit('[patch-confirm-dialogs] native window.confirm remains')
if text.count('await olcConfirm(') < replaced:
    raise SystemExit('[patch-confirm-dialogs] not every confirm was converted')

path.write_text(text)
print(f'[patch-confirm-dialogs] converted {replaced} native confirms; runtime count=0')
PY
