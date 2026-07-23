#!/usr/bin/env bash
# Olc-cost-l frontend: предупреждающая мини-модалка при переключении контроля
# доступа на «Пускать всех» (Выключено) при ВКЛЮЧЕННОЙ рандомизации — в 🎫 и 🔌,
# ГЛОБАЛЬНО (AccessControlSection) и ВЫБОРОЧНО (ClientAccessModal). Текст зависит
# от типа рандомизации (1/2) и секции (🎫 = client_id, 🔌 = крипто-ключи).
# Срабатывает при переключении на «Пускать всех» с ЛЮБОГО режима (+/Блокировать).
# СКОУП: пока «доп. настройки рандомизации» (client_id/крипто/оба) НЕ реализованы,
# скоуп = ОБА → предупреждаем и для 🎫, и для 🔌. Когда скоуп появится — гейтить
# 🎫 по client_id-скоупу, 🔌 по крипто-скоупу (см. хендофф ЭПИК A).
# Idempotent. Target: manager src/main.tsx. Run ПОСЛЕ panel-keyrand-plus-sub.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-keyrand-off-warning] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-keyrand-off-warning] {label}: already applied")
        return
    n = t.count(old)
    if n == 0:
        print(f"[patch-keyrand-off-warning] WARN {label}: anchor not found")
        return
    if n > 1:
        print(f"[patch-keyrand-off-warning] WARN {label}: anchor not unique ({n})")
        return
    t = t.replace(old, new, 1)
    changed = True
    print(f"[patch-keyrand-off-warning] {label}: ok")

# Тексты предупреждений
W_SUB_T1 = 'При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа подписка станет недоступна по оригинальному client id для всех. Не рекомендуем данное действие.'
W_SUB_T2 = 'При выключении контроля доступа (переключении на «Пускать всех») подписка станет недоступна для всех. Не рекомендуем данное действие.'
W_CONN_T1 = 'При выключении контроля доступа (переключении на «Пускать всех») и включённой рандомизации 1 типа инстансы в подписке станут недоступны по оригинальным ключам шифрования для всех. Не рекомендуем данное действие.'
W_CONN_T2 = 'При выключении контроля доступа (переключении на «Пускать всех») инстансы в подписке станут недоступны для всех. Не рекомендуем данное действие.'

# ============================ ГЛОБАЛЬНО (AccessControlSection) ============================

# 1. randType state (после randOn, уникальный якорь global)
repl(
    'localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });\n  const [randOn, setRandOn] = useState(false);',
    'localStorage.getItem("olc-conn-cleared-global") || ""; } catch { return ""; } });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
    "G randType state",
    guard='olc-conn-cleared-global") || ""; } catch { return ""; } });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
)

# 2. capture randType in loadRand
repl(
    'const b = await r.json(); setRandOn(!!b.enabled); } catch { /* ignore */ } };',
    'const b = await r.json(); setRandOn(!!b.enabled); setRandType(b.rand_type === 2 ? 2 : 1); } catch { /* ignore */ } };',
    "G loadRand randType",
    guard="setRandType(b.rand_type === 2 ? 2 : 1);",
)

# 3. G 🎫 «Выключено» onClick -> warning
repl(
    'onClick={() => { if (subOff) return; setMode("monitor"); void saveSettings({ mode: "monitor" }); }}>',
    'onClick={() => { if (subOff) return; const go = () => { setMode("monitor"); void saveSettings({ mode: "monitor" }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "' + W_SUB_T2 + '" : "' + W_SUB_T1 + '"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>',
    "G sub off warning",
    guard='const go = () => { setMode("monitor"); void saveSettings({ mode: "monitor" }); };',
)

# 4. G 🔌 «Выключено» onClick -> warning
repl(
    'onClick={() => { if (connOff) return; setEnforceConns(false); void saveSettings({ enforce_connections: false }); }}>',
    'onClick={() => { if (connOff) return; const go = () => { setEnforceConns(false); void saveSettings({ enforce_connections: false }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "' + W_CONN_T2 + '" : "' + W_CONN_T1 + '"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>',
    "G conn off warning",
    guard='const go = () => { setEnforceConns(false); void saveSettings({ enforce_connections: false }); };',
)

# ============================ ВЫБОРОЧНО (ClientAccessModal) ============================

# 5. randType state (после randOn, уникальный якорь per-client)
repl(
    'conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);',
    'conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
    "C randType state",
    guard='conn_ban: [] });\n  const [randOn, setRandOn] = useState(false);\n  const [randType, setRandType] = useState(1);',
)

# 6. capture randType in per-client fetch
repl(
    'setRandOn(!!gb.enabled || !!(cl?.randomization?.enabled)); } catch { setRandOn(!!(cl?.randomization?.enabled)); }',
    'setRandOn(!!gb.enabled || !!(cl?.randomization?.enabled)); setRandType(gb.enabled ? (gb.rand_type === 2 ? 2 : 1) : ((cl?.randomization?.rand_type) === 2 ? 2 : 1)); } catch { setRandOn(!!(cl?.randomization?.enabled)); setRandType((cl?.randomization?.rand_type) === 2 ? 2 : 1); }',
    "C fetch randType",
    guard="setRandType(gb.enabled ? (gb.rand_type === 2 ? 2 : 1)",
)

# 7. C 🎫 «Выключено» onClick -> warning
repl(
    'onClick={() => { if (subOff) return; setMode("off"); void save({ mode: "off" }); }}>',
    'onClick={() => { if (subOff) return; const go = () => { setMode("off"); void save({ mode: "off" }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "' + W_SUB_T2 + '" : "' + W_SUB_T1 + '"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>',
    "C sub off warning",
    guard='const go = () => { setMode("off"); void save({ mode: "off" }); };',
)

# 8. C 🔌 «Выключено» onClick -> warning
repl(
    'onClick={() => { if (connOff) return; setConnEnforce(false); void save({ conn_enforce: false }); }}>',
    'onClick={() => { if (connOff) return; const go = () => { setConnEnforce(false); void save({ conn_enforce: false }); }; if (randOn) { setConfirmA({ text: (randType === 2 ? "' + W_CONN_T2 + '" : "' + W_CONN_T1 + '"), ok: "Всё равно выключить", cancel: "Отмена", okCls: "red", run: go }); } else { go(); } }}>',
    "C conn off warning",
    guard='const go = () => { setConnEnforce(false); void save({ conn_enforce: false }); };',
)

if changed:
    f.write_text(t)
    print("[patch-keyrand-off-warning] OK: main.tsx updated")
else:
    print("[patch-keyrand-off-warning] no changes")
PY
