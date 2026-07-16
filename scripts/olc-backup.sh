#!/usr/bin/env bash
# olc-backup — экспорт/импорт всех данных панели через локальный API.
#
#   sudo olc-backup export [файл.json]     # по умолчанию ./olc-backup-<дата>.json
#   sudo olc-backup import <файл.json>
#
# Данные хранятся ТОЛЬКО на этом устройстве. Устойчиво к смене версий панели
# (бэкенд делает schema-независимый deep-merge). См. docs/BACKUP.md.
set -euo pipefail

CONFIG="${OLCRTC_MANAGER_CONFIG:-/etc/olcrtc-manager/config.json}"
ENVF="${OLCRTC_MANAGER_ENV_FILE:-/etc/olcrtc-manager/panel.env}"

die() { echo "[olc-backup] ОШИБКА: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || exec sudo -E bash "$0" "$@"

port=8888
if [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
  port="$(jq -r '.port // 8888' "$CONFIG" 2>/dev/null || echo 8888)"
fi
user="admin"; pass=""
if [[ -f "$ENVF" ]]; then
  user="$(grep -E '^OLCRTC_MANAGER_USER=' "$ENVF" | tail -1 | cut -d= -f2- | tr -d '"'"'"'' || true)"
  pass="$(grep -E '^OLCRTC_MANAGER_PASS=' "$ENVF" | tail -1 | cut -d= -f2- | tr -d '"'"'"'' || true)"
  user="${user:-admin}"
fi
base="http://127.0.0.1:${port}"
auth=(-u "${user}:${pass}")

cmd="${1:-}"; shift || true
case "$cmd" in
  export)
    out="${1:-olc-backup-$(date -u +%Y%m%d-%H%M%S).json}"
    curl -fsS "${auth[@]}" "$base/api/backup/export" -o "$out" \
      || die "экспорт не удался (панель запущена? верный пароль в $ENVF?)"
    echo "[olc-backup] сохранено: $out"
    echo "[olc-backup] это ВАШИ данные — хранятся только у вас; держите файл в надёжном месте."
    ;;
  import)
    in="${1:-}"; [[ -n "$in" && -f "$in" ]] || die "укажите существующий файл: olc-backup import <файл.json>"
    resp="$(curl -fsS "${auth[@]}" -X POST "$base/api/backup/import" \
      -H 'Content-Type: application/json' --data-binary @"$in")" \
      || die "импорт не удался (панель запущена? верный файл/пароль?)"
    echo "[olc-backup] ответ: $resp"
    echo "[olc-backup] перезапуск панели для применения…"
    systemctl restart olcrtc-manager 2>/dev/null || echo "[olc-backup] перезапустите вручную: systemctl restart olcrtc-manager"
    ;;
  *)
    sed -n '1,10p' "$0"; exit 1 ;;
esac
