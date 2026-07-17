#!/usr/bin/env bash
# Olc-cost-l backend fix: zapret показывался "inactive", хотя DPI-bypass работает.
# Причина: featureLiveStatus() берёт `systemctl is-active zapret`, но zapret.service —
# oneshot (применяет nftables/iptables + запускает nfqws через KillMode=none и
# завершается), поэтому is-active возвращает inactive/failed, хотя nfqws реально
# крутится и обход работает. Настоящая живость zapret = запущенный процесс nfqws
# (панель его уже детектит как out["nfqws"]). Фикс: если nfqws running, а zapret
# не active — считаем zapret active.
# Idempotent. Target: manager main.go. Run after golden copy (до/после logs-fix — неважно).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-zapret-live-status] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

if 'zapret.service — oneshot: живость определяем по nfqws' in t:
    print("[patch-zapret-live-status] already applied")
    sys.exit(0)

anchor = '''	out["nfqws"] = "unknown"
	if b, err := exec.Command("pidof", "nfqws").Output(); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		out["nfqws"] = "running"
	} else {
		out["nfqws"] = "stopped"
	}'''

repl = '''	out["nfqws"] = "unknown"
	if b, err := exec.Command("pidof", "nfqws").Output(); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		out["nfqws"] = "running"
	} else {
		out["nfqws"] = "stopped"
	}
	// zapret.service — oneshot: живость определяем по nfqws, а не по is-active.
	// Сервис применяет правила фаервола и запускает nfqws (KillMode=none), затем
	// завершается — is-active даёт inactive, хотя DPI-bypass реально активен.
	if out["nfqws"] == "running" && out["zapret"] != "active" {
		out["zapret"] = "active"
	}'''

if anchor in t:
    t = t.replace(anchor, repl, 1)
    f.write_text(t)
    print("[patch-zapret-live-status] OK: zapret live status derived from nfqws")
else:
    print("[patch-zapret-live-status] WARN: nfqws anchor not found — skip")
PY
