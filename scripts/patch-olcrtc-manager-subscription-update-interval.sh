#!/usr/bin/env bash
# Olc-cost-l backend: реальное управление автообновлением подписки у клиента.
#
# olcbox (клиент) читает интервал автообновления подписки из HTTP-заголовка
# ответа шлюза подписки `profile-update-interval: N` (N в ЧАСАХ, coerce 1..720;
# olcbox: LocationsDatasource.profileUpdateIntervalHours). Строка `#refresh:` в
# ТЕЛЕ подписки olcbox'ом для расписания НЕ используется (только отображается).
# Поэтому: шлюз подписки теперь отдаёт заголовок profile-update-interval,
# вычисленный из того же значения refresh (глоб. cfg.Refresh + per-client
# client.Refresh, приоритет per-client — effectiveRefresh). #refresh в теле
# ОСТАЁТСЯ как отображение заданного значения. olcbox НЕ трогаем.
#
# Гранулярность olcbox — целые часы (min 1ч): refresh "10m"/"45s" → 1ч,
# "24h" → 24, "2d" → 48, ">720h" → 720. Пустой refresh → заголовок НЕ шлём
# (olcbox дефолтит на 24ч). Значение в часах также используется автосменой
# ключей (следующий этап).
#
# Idempotent. Target: manager main.go. Run ПОСЛЕ subscription-randomization
# (тот переписывает subscriptionHandler).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-sub-update-interval] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib, re
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Хелперы: refreshToHours + subscriptionRefreshHours (после effectiveRefresh) ---
if 'func refreshToHours(' not in t:
    anchor = 'func effectiveRefresh(globalRefresh, clientRefresh string) string {'
    helpers = '''// refreshToHours переводит строку refresh (форматы s/m/h/d, см. validateRefresh)
// в целые ЧАСЫ для заголовка olcbox profile-update-interval. olcbox коэрсит в
// 1..720, поэтому <1ч округляем ВВЕРХ до 1ч. Пустой/битый refresh → 0 (не слать
// заголовок → olcbox использует свой дефолт 24ч).
func refreshToHours(refresh string) int {
	refresh = strings.TrimSpace(refresh)
	if len(refresh) < 2 {
		return 0
	}
	unit := refresh[len(refresh)-1]
	n, err := strconv.Atoi(refresh[:len(refresh)-1])
	if err != nil || n <= 0 {
		return 0
	}
	var hours int
	switch unit {
	case 's':
		hours = (n + 3599) / 3600
	case 'm':
		hours = (n + 59) / 60
	case 'h':
		hours = n
	case 'd':
		hours = n * 24
	default:
		return 0
	}
	if hours < 1 {
		hours = 1
	}
	if hours > 720 {
		hours = 720
	}
	return hours
}

// subscriptionRefreshHours — эффективный интервал автообновления (в часах) для
// клиента: per-client refresh переопределяет глобальный (effectiveRefresh).
// clientID, которого нет в cfg.Clients (дефолтная подписка), берёт глобальный.
func subscriptionRefreshHours(cfg Config, clientID string) int {
	refresh := cfg.Refresh
	for _, c := range cfg.Clients {
		if c.ClientID == clientID {
			refresh = effectiveRefresh(cfg.Refresh, c.Refresh)
			break
		}
	}
	return refreshToHours(refresh)
}

'''
    t = t.replace(anchor, helpers + anchor, 1)
    changed = True
    print("[patch-sub-update-interval] added refreshToHours + subscriptionRefreshHours")
else:
    print("[patch-sub-update-interval] helpers already present")

# --- 2. Отдать заголовок profile-update-interval в subscriptionHandler ---
# subscriptionHandler переписан патчем subscription-randomization; он резолвит
# resolvedClientID и пишет Content-Type + тело. Вставляем установку заголовка.
old_write = '''\t\tw.Header().Set("Content-Type", "text/plain; charset=utf-8")
\t\t_, _ = w.Write([]byte(sub))'''
new_write = '''\t\tif hours := subscriptionRefreshHours(cfg, resolvedClientID); hours > 0 {
\t\t\tw.Header().Set("profile-update-interval", strconv.Itoa(hours))
\t\t}
\t\tw.Header().Set("Content-Type", "text/plain; charset=utf-8")
\t\t_, _ = w.Write([]byte(sub))'''
if 'w.Header().Set("profile-update-interval"' in t:
    print("[patch-sub-update-interval] header already set")
elif old_write in t:
    t = t.replace(old_write, new_write, 1)
    changed = True
    print("[patch-sub-update-interval] subscriptionHandler now sets profile-update-interval")
else:
    print("[patch-sub-update-interval] WARN: subscriptionHandler write anchor not found (порядок патчей?) — header NOT set")

if changed:
    f.write_text(t)
    print("[patch-sub-update-interval] OK: main.go updated")
else:
    print("[patch-sub-update-interval] no changes (idempotent)")
PY
