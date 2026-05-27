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
