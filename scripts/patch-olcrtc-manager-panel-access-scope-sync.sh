#!/usr/bin/env bash
set -euo pipefail

tsx=${1:?usage: $0 <main.tsx>}

python3 - "$tsx" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

# Connection + is a real active mode. Older UI derived connOff only from the
# enforce boolean, so labels, dimming and allowed-list controls incorrectly
# claimed that + was "off".
text, conn_state_count = re.subn(
    r'  const connOff = !([A-Za-z][A-Za-z0-9_]*);\n  const connKr = (connKeyrand && randConn);',
    r'  const connKr = \2;\n  const connOff = !\1 && !connKr;',
    text,
)
if conn_state_count not in (0, 2):
    raise SystemExit(f"unexpected connection active-state replacements: {conn_state_count}")
if conn_state_count == 0 and text.count('&& !connKr;') != 2:
    raise SystemExit("connection + active-state anchors not found")

# The enforce selector used !connOff as its selected/early-return condition.
# Once + is correctly active, that expression is also true for + and made two
# modes look selected while preventing a switch from + to enforce.
text, enforce_class_count = re.subn(
    r'className=\{!connOff \?',
    'className={(!connOff && !connKr) ?',
    text,
)
text, enforce_click_count = re.subn(
    r'onClick=\{\(\) => \{ if \(!connOff\) return;',
    'onClick={() => { if (!connOff && !connKr) return;',
    text,
)
if enforce_class_count not in (0, 2) or enforce_click_count not in (0, 2):
    raise SystemExit(f"unexpected connection enforce selector replacements: class={enforce_class_count} click={enforce_click_count}")
if enforce_class_count == 0 and text.count('className={(!connOff && !connKr) ?') != 2:
    raise SystemExit("connection enforce selected-state anchors not found")
if enforce_click_count == 0 and text.count('if (!connOff && !connKr) return;') != 2:
    raise SystemExit("connection enforce click-state anchors not found")

# Both global and per-client dialogs already expose randScope/randType. Give all
# four + buttons the same scope-aware explanation instead of a stale generic one.
marker = '  const dimCls = (off: boolean) => (off ? " pointer-events-none opacity-40 select-none" : "");'
helper = '''  const olcKeyrandHint = (target: "sub" | "conn") => {
    const typeText = randType === 2
      ? "Тип 2: рандомизированные значения меняются динамически."
      : "Тип 1: для неизвестных используется статичное рандомизированное значение.";
    if (target === "sub") {
      if (randScope === "client_id") return `Разрешённые получают подписку по оригинальному client_id; неизвестные — только по рандомизированному. Криптоключи не рандомизируются и остаются оригинальными для всех. ${typeText} Бан действует всегда.`;
      return `Разрешённые используют оригинальные client_id и криптоключи. Неизвестным нужен рандомизированный client_id, а в полученной подписке — рандомизированные криптоключи. ${typeText} Бан действует всегда.`;
    }
    if (randScope === "crypto") return `Разрешённые подключаются по оригинальным криптоключам; неизвестные — только по рандомизированным. Client_id не рандомизируется и остаётся оригинальным для всех. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
    return `Разрешённые используют оригинальные криптоключи и client_id; неизвестным нужны рандомизированные значения. ${typeText} Отключение разрешения сбрасывает живую сессию по оригинальному ключу; бан действует всегда.`;
  };
'''
if 'const olcKeyrandHint = (target:' not in text:
    count = text.count(marker)
    if count != 2:
        raise SystemExit(f"expected 2 access dimCls markers, got {count}")
    text = text.replace(marker, helper + marker)

text, sub_count = re.subn(
    r'title="[^"]*"(\s*\n\s*className=\{subKeyrand\s*\?)',
    r'title={olcKeyrandHint("sub")}\1',
    text,
)
text, conn_count = re.subn(
    r'title="[^"]*"(\s*\n\s*className=\{connKr\s*\?)',
    r'title={olcKeyrandHint("conn")}\1',
    text,
)
if sub_count not in (0, 2) or conn_count not in (0, 2):
    raise SystemExit(f"unexpected + tooltip replacements: sub={sub_count} conn={conn_count}")
if sub_count == 0 and text.count('title={olcKeyrandHint("sub")}') != 2:
    raise SystemExit("subscription + tooltips not found")
if conn_count == 0 and text.count('title={olcKeyrandHint("conn")}') != 2:
    raise SystemExit("connection + tooltips not found")

# Per-client global snapshot must include modes and connection targeting, not
# just append list entries.
old_glob = '''        conn_devices: Array.isArray(sb.conn_devices) ? sb.conn_devices : [],
        conn_ban: Array.isArray(sb.conn_ban) ? sb.conn_ban : [],
      });'''
new_glob = '''        conn_devices: Array.isArray(sb.conn_devices) ? sb.conn_devices : [],
        conn_ban: Array.isArray(sb.conn_ban) ? sb.conn_ban : [],
        mode: sb.mode,
        conn_mode: sb.conn_mode,
        enforce_connections: !!sb.enforce_connections,
        conn_scope: sb.conn_scope === "selective" ? "selective" : "all",
        conn_instances: Array.isArray(sb.conn_instances) ? sb.conn_instances : [],
        ban_no_hwid: !!sb.ban_no_hwid,
      });'''
if old_glob in text:
    text = text.replace(old_glob, new_glob, 1)
elif new_glob not in text:
    raise SystemExit("global access snapshot anchor not found")

start = text.find('  const isSynced = () =>', text.find('function ClientAccessModal('))
end = text.find('  const setSyncHiddenPersist', start)
if start < 0 or end < 0:
    raise SystemExit("per-client sync block not found")
old_sync = text[start:end]
new_sync = '''  const syncSubMode = glob.mode === "enforce" ? "enforce" : (glob.mode === "keyrand" && randSub ? "keyrand" : "off");
  const syncConnMode = (glob.conn_mode === "enforce" || glob.enforce_connections)
    ? "enforce"
    : (glob.conn_mode === "keyrand" && randConn ? "keyrand" : "off");
  const sameRooms = (a: string[], b: string[]) => [...(a || [])].sort().join("\\n") === [...(b || [])].sort().join("\\n");
  const isSynced = () =>
    (glob.devices || []).every((d: Dev) => hasHwid(allow, d.hwid)) &&
    (glob.ban || []).every((d: Dev) => hasHwid(ban, d.hwid)) &&
    (glob.conn_devices || []).every((d: Dev) => hasHwid(connAllow, d.hwid)) &&
    (glob.conn_ban || []).every((d: Dev) => hasHwid(connBan, d.hwid)) &&
    (glob.allow_ips || []).every((x: any) => (allowIps || []).some((y: any) => y.ip === x.ip)) &&
    (glob.ban_ips || []).every((x: any) => (banIps || []).some((y: any) => y.ip === x.ip)) &&
    mode === syncSubMode &&
    (connKeyrand ? "keyrand" : connEnforce ? "enforce" : "off") === syncConnMode &&
    connScope === (glob.conn_scope || "all") &&
    sameRooms(connInstances, glob.conn_instances || []) &&
    banNoHwid === !!glob.ban_no_hwid;
  const syncFromGlobal = () => {
    void save({
      allow: mergeDev(allow, glob.devices),
      ban: mergeDev(ban, glob.ban),
      conn_allow: mergeDev(connAllow, glob.conn_devices),
      conn_ban: mergeDev(connBan, glob.conn_ban),
      allow_ips: mergeIp(allowIps, glob.allow_ips),
      ban_ips: mergeIp(banIps, glob.ban_ips),
      ban_no_hwid: !!glob.ban_no_hwid,
      mode: syncSubMode,
      conn_mode: syncConnMode,
      conn_enforce: syncConnMode === "enforce",
      conn_scope: glob.conn_scope || "all",
      conn_instances: Array.isArray(glob.conn_instances) ? glob.conn_instances : [],
    });
  };
'''
if 'const syncSubMode = glob.mode' not in old_sync:
    text = text[:start] + new_sync + text[end:]

# Tell the user that synchronization now includes effective modes and scope.
text = text.replace(
    'Скопировать все глобальные разрешённые/забаненные/IP в эту подписку (объединение, ничего не удаляя).',
    'Скопировать глобальные режимы доступа, область инстансов и все разрешённые/забаненные/IP. Списки объединяются без удаления локальных записей.',
    1,
)

path.write_text(text)
PY

echo "patched adaptive + help and complete per-client global sync"
