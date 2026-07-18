#!/usr/bin/env bash
# Olc-cost-l backend: cleanup смежных конфигов при УДАЛЕНИИ клиента (Баг 1).
# Симптом: удалил клиента, но его запись осталась в access-control.json clients{}
# (и, как следствие, «мёртвые» per-подписочные записи копятся; при повторном
# создании клиента с тем же id всплывают старые настройки доступа).
# Рандомизация клиента (Client.Randomization) — поле самого клиента в config.json,
# оно исчезает вместе с клиентом при deleteClient, отдельной чистки не требует.
# Здесь чистим ТОЛЬКО отдельный файл access-control.json (его deleteClient не трогал).
# Требует: olcAccessLoad/olcAccessSave (patch-olcrtc-manager-access-control-api).
# Run ПОСЛЕ access-control-api. Idempotent. Target: manager main.go.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-delete-client-cleanup] ERROR: $MAIN_GO not found"; exit 1; }

if grep -q 'olcCleanupClientAccess' "$MAIN_GO"; then
  echo "[patch-delete-client-cleanup] already applied"
  exit 0
fi

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# 1. Хелпер olcCleanupClientAccess перед func deleteClient.
anchor = 'func deleteClient(configPath, clientID string) error {'
if anchor not in t:
    print("[patch-delete-client-cleanup] ERROR: deleteClient anchor not found")
    sys.exit(1)

if 'func olcCleanupClientAccess(' not in t:
    helper = (
        '// olcCleanupClientAccess — при удалении клиента убирает его per-подписочную\n'
        '// запись из access-control.json (иначе копятся мёртвые clients{} записи —\n'
        '// Баг 1). Best-effort: ошибки только логируем, удаление клиента не валим.\n'
        'func olcCleanupClientAccess(clientID string) {\n'
        '\tclientID = strings.TrimSpace(clientID)\n'
        '\tif clientID == "" {\n'
        '\t\treturn\n'
        '\t}\n'
        '\tac := olcAccessLoad()\n'
        '\tif ac.Clients == nil {\n'
        '\t\treturn\n'
        '\t}\n'
        '\tif _, ok := ac.Clients[clientID]; !ok {\n'
        '\t\treturn\n'
        '\t}\n'
        '\tdelete(ac.Clients, clientID)\n'
        '\tif err := olcAccessSave(ac); err != nil {\n'
        '\t\tlog.Printf("olc-access: cleanup client %q on delete: %v", clientID, err)\n'
        '\t}\n'
        '}\n\n'
    )
    t = t.replace(anchor, helper + anchor, 1)
    changed = True
    print("[patch-delete-client-cleanup] helper olcCleanupClientAccess added")

# 2. Врезка вызова в конце deleteClient (внутри тела функции).
fn_start = t.index(anchor)
fn_end = t.index('\n}\n', fn_start) + len('\n}\n')
block = t[fn_start:fn_end]
old_tail = '\treturn saveConfig(configPath, cfg)\n}'
new_tail = (
    '\tif err := saveConfig(configPath, cfg); err != nil {\n'
    '\t\treturn err\n'
    '\t}\n'
    '\tolcCleanupClientAccess(clientID)\n'
    '\treturn nil\n'
    '}'
)
if 'olcCleanupClientAccess(clientID)' not in block:
    if old_tail not in block:
        print("[patch-delete-client-cleanup] ERROR: deleteClient tail anchor not found")
        sys.exit(1)
    new_block = block.replace(old_tail, new_tail, 1)
    t = t[:fn_start] + new_block + t[fn_end:]
    changed = True
    print("[patch-delete-client-cleanup] deleteClient wired to cleanup")

if changed:
    f.write_text(t)
print("[patch-delete-client-cleanup] ok")
PY
