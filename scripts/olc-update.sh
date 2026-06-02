#!/usr/bin/env bash
# Short updater command for already-installed Olc-cost-l hosts.
set -euo pipefail

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

detect_repo() {
  if [[ -d /opt/Olc-cost-l/.git ]]; then
    echo "/opt/Olc-cost-l"
    return
  fi
  if [[ -d /opt/olcrtc/.git ]]; then
    echo "/opt/olcrtc"
    return
  fi
  if [[ -L /opt/olcrtc ]] && [[ -d "$(readlink -f /opt/olcrtc)/.git" ]]; then
    readlink -f /opt/olcrtc
    return
  fi
  return 1
}

_script="${BASH_SOURCE[0]}"
while [[ -L "$_script" ]]; do
  _script="$(readlink -f "$_script")"
done
SCRIPT_DIR="$(cd "$(dirname "$_script")" && pwd)"
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"
# shellcheck source=lib-olc-core.sh
source "$SCRIPT_DIR/lib-olc-core.sh"
# shellcheck source=lib-disk-preflight.sh
source "$SCRIPT_DIR/lib-disk-preflight.sh"
# shellcheck source=lib-cache-cleanup.sh
source "$SCRIPT_DIR/lib-cache-cleanup.sh"
# shellcheck source=lib-vps-backup.sh
source "$SCRIPT_DIR/lib-vps-backup.sh"

olc_update_has_tty() {
  [ -t 0 ] || { [ -e /dev/tty ] && : </dev/tty; } 2>/dev/null
}

main() {
  need_root "$@"
  local repo profile_arg=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --show-profile) profile_show; exit 0 ;;
      --profile) profile_arg=(--profile) ;;
      --force-sha-update) export OLCRTC_FORCE_SHA_UPDATE=1 ;;
      --manager-stable) export OLC_MANAGER_STABLE=1 ;;
      --manager-latest) export OLC_MANAGER_LATEST=1 ;;
    esac
  done
  repo="$(detect_repo)" || {
    echo "Olc-cost-l repo not found. Install first, then run: olc-update" >&2
    exit 1
  }
  cd "$repo"
  export OLC_REPO_ROOT="$repo"
  
  echo "Проверка актуальности репозитория (ветка main)..." >&2
  local_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  remote_sha="$(git ls-remote origin main 2>/dev/null | awk '{print $1}' || true)"
  
  if [[ -n "$local_sha" && "$local_sha" == "$remote_sha" ]]; then
    echo "Репозиторий уже актуален." >&2
    git log -1 --format="Текущая версия: %h - %s (%cd)" --date=format:"%Y-%m-%d %H:%M" >&2
    if olc_update_has_tty; then
      read -r -p "Всё равно запустить доустановку/обновление скриптов? (1 - Да, 2 - Нет): " _ans </dev/tty || _ans="1"
      if [[ "${_ans,,}" != "1" && "${_ans,,}" != "да" && "${_ans,,}" != "-да" && "${_ans,,}" != "- да" && "${_ans,,}" != "y" && "${_ans,,}" != "yes" ]]; then
        echo "Отмена." >&2
        exit 0
      fi
    fi
  else
    if [[ -n "$remote_sha" ]]; then
      echo "Доступны обновления репозитория." >&2
    fi
    if olc_update_has_tty; then
      read -r -p "Скачать обновления и установить? (1 - Да, 2 - Нет): " _ans </dev/tty || _ans="1"
      if [[ "${_ans,,}" != "1" && "${_ans,,}" != "да" && "${_ans,,}" != "-да" && "${_ans,,}" != "- да" && "${_ans,,}" != "y" && "${_ans,,}" != "yes" ]]; then
        echo "Отмена." >&2
        exit 0
      fi
    fi
  fi

  olc_preflight_disk_space "olc-update" || exit 1
  if [[ "$(df -Pm / 2>/dev/null | awk 'NR==2 {print $5+0}')" -ge 95 ]]; then
    olc_cleanup_build_caches "olc-update-pre-git" || true
  fi
  export _OLC_DISK_PROMPTED=1 # Чтобы не спрашивать дважды в agent-bootstrap.sh
  olc_preflight_vps_backup "olc-update" || true
  export OLC_VPS_BACKUP_DISABLE=1 # Чтобы не делать бэкап дважды
  
  olc_git_safe_register "$repo"
  olc_git "$repo" pull --ff-only origin main
  # Re-read profile id if passed as --profile <id>
  local boot_args=(--update)
  local i=1
  while [[ $i -le $# ]]; do
    eval "arg=\${$i}"
    if [[ "$arg" == "--profile" ]]; then
      next=$((i + 1))
      eval "pid=\${$next}"
      boot_args+=(--profile "$pid")
      i=$((i + 2))
      continue
    fi
    if [[ "$arg" != "--show-profile" ]]; then
      boot_args+=("$arg")
    fi
    i=$((i + 1))
  done
  bash scripts/agent-bootstrap.sh "${boot_args[@]}"
}

main "$@"
