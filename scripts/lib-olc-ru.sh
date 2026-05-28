#!/usr/bin/env bash
# Русские сообщения для install/bootstrap/patches (OLC_LANG=ru по умолчанию).
[[ -n "${_OLC_RU_LOADED:-}" ]] && return 0
_OLC_RU_LOADED=1

OLC_LANG="${OLC_LANG:-ru}"

# Универсальный лог этапа: olc_log_step "текст" / olc_log_step en "text"
olc_log_step() {
  if [[ "${OLC_LANG}" == en ]]; then
    echo "==> $*"
    return
  fi
  local msg="$*"
  case "$msg" in
    "UPDATE:"*) echo "==> ОБНОВЛЕНИЕ: списки, патчи, Tor, zapret, systemd (можно продолжить с --resume)" ;;
    "install nodejs"*) echo "==> Установка nodejs/npm (нужны для сборки панели)" ;;
    *) echo "==> $msg" ;;
  esac
}

olc_log_apply() {
  if [[ "${OLC_LANG}" == en ]]; then
    echo "[apply-patches] $*"
    return
  fi
  local msg="$*"
  case "$msg" in
    "olcrtc patches in "*) echo "[патчи] olcrtc: $msg" | sed 's/olcrtc patches in /каталог /' ;;
    "manager patches in "*) echo "[патчи] панель manager: $msg" | sed 's/manager patches in /каталог /' ;;
    "skip "*) echo "[патчи] пропуск: ${msg#skip }" ;;
    "WARN:"*) echo "[патчи] внимание: ${msg#WARN: }" ;;
    "ERROR:"*) echo "[патчи] ОШИБКА: ${msg#ERROR: }" ;;
    *) echo "[патчи] $msg" ;;
  esac
}

# Сообщения [state] из lib-install-state.sh
olc_state_line() {
  if [[ "${OLC_LANG}" == en ]]; then
    echo "[state] $*"
    return
  fi
  local line="$*"
  line="${line/→ patches/→ патчи (olcrtc + панель manager)}"
  line="${line/→ packages/→ пакеты apt}"
  line="${line/→ go-toolchain/→ Go toolchain}"
  line="${line/✓ patches/✓ патчи применены}"
  line="${line/✗ patches/✗ патчи — ошибка}"
  line="${line/skip /пропуск (уже сделано): }"
  line="${line/ABORT/СТОП}"
  line="${line/Resume with:/Продолжить:}"
  echo "[этап] $line"
}

olc_patch_skip_msg() {
  echo "[патчи] пропуск файла olcrtc-manager-main.go.patch — патч уже в upstream или не подходит к этой версии панели (это нормально)." >&2
}

olc_run_with_progress() {
  local label="$1"
  shift
  local interval="${OLC_PROGRESS_INTERVAL:-10}"
  local started pid rc elapsed

  echo "[ожидание] ${label} — это может занять несколько минут" >&2
  started="$(date +%s)"
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$interval"
    if kill -0 "$pid" 2>/dev/null; then
      elapsed=$(( $(date +%s) - started ))
      echo "[ожидание] ${label} — идёт ${elapsed}с, всё нормально" >&2
    fi
  done
  rc=0
  wait "$pid" || rc=$?
  elapsed=$(( $(date +%s) - started ))
  if [[ "$rc" -eq 0 ]]; then
    echo "[ожидание] ${label} — готово (${elapsed}с)" >&2
  else
    echo "[ожидание] ${label} — ошибка rc=${rc} (${elapsed}с)" >&2
  fi
  return "$rc"
}

olc_detect_panel_host() {
  local host=""
  if command -v curl >/dev/null 2>&1; then
    host="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$host" ]]; then
    host="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  fi
  if [[ -z "$host" ]]; then
    host="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"
  fi
  printf '%s\n' "${host:-127.0.0.1}"
}

olc_panel_access_mode() {
  if [[ -n "${PANEL_ACCESS:-}" ]]; then
    printf '%s\n' "$PANEL_ACCESS"
    return 0
  fi
  if [[ -f /etc/olcrtc-manager/deploy-profile.json ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.panel.access // "ip"' /etc/olcrtc-manager/deploy-profile.json 2>/dev/null || echo ip
    return 0
  fi
  if [[ -f /etc/olcrtc-manager/panel.env ]]; then
    local access
    access="$(grep -E '^[[:space:]]*OLCRTC_PANEL_ACCESS=' /etc/olcrtc-manager/panel.env | tail -1 | cut -d= -f2- | tr -d '"'"'" || true)"
    [[ -n "$access" ]] && { printf '%s\n' "$access"; return 0; }
  fi
  echo ip
}

olc_print_finish_help() {
  local port="${1:-8888}"
  local host public_url panel_access
  host="$(olc_detect_panel_host)"
  panel_access="$(olc_panel_access_mode)"
  if [[ "$panel_access" == "ssh" ]]; then
    public_url="http://127.0.0.1:${port}/admin"
  else
    public_url="http://${host}:${port}/admin"
  fi

  cat >&2 <<EOF

══════════════════════════════════════════════════════════
  Olc-cost-l: установка завершена
══════════════════════════════════════════════════════════
  Панель:
    ${public_url}

  SSH-туннель:
    ssh -L ${port}:127.0.0.1:${port} root@${host}
    затем открыть: http://127.0.0.1:${port}/admin

  Короткие команды:
    sudo olc-update          обновить / доустановить компоненты
    sudo olc-feature status  статус Tor/Split/Zapret/WARP
    sudo olc-cleanup-caches  очистить сборочные кэши
    sudo olc-purge           удалить стек OlcRTC с VPS

  Документация:
    ${REPO_ROOT:-/opt/Olc-cost-l}/docs/VPS-SETUP.md
══════════════════════════════════════════════════════════

EOF
}
