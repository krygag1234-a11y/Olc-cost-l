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

# Guard the four log-card allow actions explicitly: two subscription dialogs
# and two connection dialogs must be gated by the effective off state, which is
# false while + is active.
if text.count('!known && (subOff') != 2:
    raise SystemExit("expected two subscription log-card allow gates")
if text.count('!known && (connOff') != 2:
    raise SystemExit("expected two connection log-card allow gates")

# A disabled allowlist row is not an active permission.  Attempt cards must
# therefore offer "allow" again, and that action must re-enable the existing
# row instead of being swallowed by the duplicate guard.  Keep this symmetric
# in the global/per-client subscription and connection dialogs.
active_replacements = {
    'const isKnown = (hwid: string) => devices.some((d) => (d.hwid || "").toLowerCase() === hwid.toLowerCase());':
        'const isKnown = (hwid: string) => devices.some((d) => (d.hwid || "").toLowerCase() === hwid.toLowerCase() && d.enabled !== false);',
    'const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase());':
        'const known = allow.some((d) => d.hwid.toLowerCase() === hwid.toLowerCase() && d.enabled !== false);',
    'const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());':
        'const known = connDevices.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);',
    'const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase());':
        'const known = connAllow.some((d) => d.hwid.toLowerCase() === dev.toLowerCase() && d.enabled !== false);',
    'const ipAllowed = ipIn(allowedIps, aip);':
        'const ipAllowed = allowedIps.some((x: any) => x.ip === aip && x.enabled !== false);',
    'const ipAllowed = ipIn(allowIps, aip);':
        'const ipAllowed = allowIps.some((x: any) => x.ip === aip && x.enabled !== false);',
}
for old, new in active_replacements.items():
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit(f"active allow-entry anchor not found: {old}")

reactivate_replacements = {
    'const h = (hwid || "").trim(); if (!h || inL(connDevices, h)) return;':
        'const h = (hwid || "").trim(); if (!h) return;\n    const existing = connDevices.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());\n    if (existing) { if (existing.enabled === false) void saveSettings({ conn_devices: connDevices.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }',
    'const h = (hwid || "").trim(); if (!h || inL(devices, h)) return;':
        'const h = (hwid || "").trim(); if (!h) return;\n    const existing = devices.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());\n    if (existing) { if (existing.enabled === false) await saveSettings({ devices: devices.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }',
    'const v = (ip || "").trim(); if (!v || ipIn(allowedIps, v)) return;':
        'const v = (ip || "").trim(); if (!v) return;\n    const existing = allowedIps.find((x: any) => x.ip === v);\n    if (existing) { if (existing.enabled === false) await saveSettings({ allowed_ips: allowedIps.map((x: any) => x === existing ? { ...x, enabled: true } : x) }); return; }',
    'h = (h || "").trim(); if (!h || inList(connAllow, h)) return;':
        'h = (h || "").trim(); if (!h) return;\n    const existing = connAllow.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());\n    if (existing) { if (existing.enabled === false) void save({ conn_allow: connAllow.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }',
    'const v = (ip || "").trim(); if (!v || ipIn(allowIps, v)) return;':
        'const v = (ip || "").trim(); if (!v) return;\n    const existing = allowIps.find((x: any) => x.ip === v);\n    if (existing) { if (existing.enabled === false) void save({ allow_ips: allowIps.map((x: any) => x === existing ? { ...x, enabled: true } : x) }); return; }',
    'h = (h || "").trim(); if (!h || inList(allow, h)) return;':
        'h = (h || "").trim(); if (!h) return;\n    const existing = allow.find((d) => (d.hwid || "").toLowerCase() === h.toLowerCase());\n    if (existing) { if (existing.enabled === false) void save({ allow: allow.map((d) => d === existing ? { ...d, enabled: true } : d) }); return; }',
}
for old, new in reactivate_replacements.items():
    if old in text:
        text = text.replace(old, new, 1)
    elif new not in text:
        raise SystemExit(f"allow reactivation anchor not found: {old}")

# Do not let a stale raw connOff label contradict the effective + state.
text, conn_label_count = re.subn(
    r'\{connOff \? " — [^"]*«Выключено»" : ""\}',
    lambda m: m.group(0).replace('{connOff ?', '{(connOff && !connKr) ?'),
    text,
)
if conn_label_count not in (0, 2):
    raise SystemExit(f"unexpected connection off-label replacements: {conn_label_count}")
if conn_label_count == 0 and text.count('{(connOff && !connKr) ? " — ') < 2:
    raise SystemExit("connection effective off-label anchors not found")

# Randomization can be changed while either access dialog remains mounted.
# Refresh its effective global/per-client type and scope so all four + hints
# cannot keep a stale type from the previously active randomization source.
rand_mount = '  useEffect(() => { void loadAll(); }, []);'
rand_refresh = '''  useEffect(() => { void loadAll(); }, []);
  useEffect(() => {
    const refreshRand = () => { void loadRand(); };
    window.addEventListener("olc-randomization-saved", refreshRand);
    const id = window.setInterval(refreshRand, 1500);
    return () => { window.removeEventListener("olc-randomization-saved", refreshRand); window.clearInterval(id); };
  }, []);'''
if 'window.addEventListener("olc-randomization-saved", refreshRand);' not in text:
    count = text.count(rand_mount)
    if count != 1:
        raise SystemExit(f"expected global access randomization mount anchor, got {count}")
    text = text.replace(rand_mount, rand_refresh)
elif text.count('window.addEventListener("olc-randomization-saved", refreshRand);') != 1:
    raise SystemExit("expected randomization refresh in global access dialog")

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

client_modal = text.find('function ClientAccessModal(')
is_synced_start = text.find('  const isSynced = () =>', client_modal)
existing_modes_start = text.find('  const syncSubMode = glob.mode', client_modal)
start = existing_modes_start if 0 <= existing_modes_start < is_synced_start else is_synced_start
end = text.find('  const setSyncHiddenPersist', is_synced_start)
if client_modal < 0 or is_synced_start < 0 or start < 0 or end < 0:
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
