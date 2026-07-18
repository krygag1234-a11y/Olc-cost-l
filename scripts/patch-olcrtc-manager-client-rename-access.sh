#!/usr/bin/env bash
# Olc-cost-l backend (Этап 5A эпика): при СМЕНЕ client_id (Edit) мигрировать
# per-подписочную запись access-control.json clients{} со старого id на новый,
# чтобы настройки контроля доступа не осиротели (рандомизация — поле Client в
# config.json, переезжает с клиентом сама при переименовании).
# Требует: olcAccessLoad/olcAccessSave (access-control-api). Run ПОСЛЕ него.
# Idempotent. Target: manager main.go.
set -euo pipefail
MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-client-rename-access] ERROR: $MAIN_GO not found"; exit 1; }

if grep -q 'olcMigrateClientAccess' "$MAIN_GO"; then
  echo "[patch-client-rename-access] already applied"
  exit 0
fi

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

anchor = 'func updateClientFromRequest('
if anchor not in t:
    print("[patch-client-rename-access] ERROR: updateClientFromRequest not found"); sys.exit(1)

# 1. Хелпер olcMigrateClientAccess перед updateClientFromRequest.
helper = (
    '// olcMigrateClientAccess — при переименовании клиента переносит его запись\n'
    '// в access-control.json clients{} со старого id на новый (иначе настройки\n'
    '// контроля доступа осиротеют под старым id). Best-effort.\n'
    'func olcMigrateClientAccess(oldID, newID string) {\n'
    '\toldID = strings.TrimSpace(oldID)\n'
    '\tnewID = strings.TrimSpace(newID)\n'
    '\tif oldID == "" || newID == "" || oldID == newID {\n'
    '\t\treturn\n'
    '\t}\n'
    '\tac := olcAccessLoad()\n'
    '\tif ac.Clients == nil {\n'
    '\t\treturn\n'
    '\t}\n'
    '\tcc, ok := ac.Clients[oldID]\n'
    '\tif !ok {\n'
    '\t\treturn\n'
    '\t}\n'
    '\tac.Clients[newID] = cc\n'
    '\tdelete(ac.Clients, oldID)\n'
    '\tif err := olcAccessSave(ac); err != nil {\n'
    '\t\tlog.Printf("olc-access: migrate client %q->%q on rename: %v", oldID, newID, err)\n'
    '\t}\n'
    '}\n\n'
)
t = t.replace(anchor, helper + anchor, 1)

# 2. Врезка миграции в конец updateClientFromRequest (по позиции ПОСЛЕ старта функции).
fn = t.index('func updateClientFromRequest(')
tail_old = '\t\treturn saveConfig(configPath, cfg)\n\t}\n\treturn fmt.Errorf("client %q not found", clientID)\n}'
idx = t.find(tail_old, fn)
if idx == -1:
    print("[patch-client-rename-access] ERROR: updateClientFromRequest tail not found"); sys.exit(1)
tail_new = (
    '\t\tif err := saveConfig(configPath, cfg); err != nil {\n'
    '\t\t\treturn err\n'
    '\t\t}\n'
    '\t\tif nextClientID != clientID {\n'
    '\t\t\tolcMigrateClientAccess(clientID, nextClientID)\n'
    '\t\t}\n'
    '\t\treturn nil\n'
    '\t}\n'
    '\treturn fmt.Errorf("client %q not found", clientID)\n'
    '}'
)
t = t[:idx] + tail_new + t[idx+len(tail_old):]

f.write_text(t)
print("[patch-client-rename-access] ok: helper + updateClientFromRequest wired")
PY
