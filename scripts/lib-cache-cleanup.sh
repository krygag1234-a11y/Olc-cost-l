#!/usr/bin/env bash
# Shared cleanup for build/runtime caches left by Olc-cost-l scripts.
[[ -n "${_OLC_CACHE_CLEANUP_LOADED:-}" ]] && return 0
_OLC_CACHE_CLEANUP_LOADED=1

# Load output library if available
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$_script_dir/lib-output.sh" ]]; then
  # shellcheck source=lib-output.sh
  source "$_script_dir/lib-output.sh"
fi

olc_cleanup_log() {
  # При активном прогресс-баре НЕ выводить шаги (накладываются на spinner)
  if [[ "${_OLCRTC_PROGRESS_ACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  if declare -f olc_print_step >/dev/null 2>&1; then
    olc_print_step "$*"
  else
    echo "[olc-cleanup] $*" >&2
  fi
}

olc_cleanup_go_caches() {
  local mode="${1:-go-only}"
  [[ "${OLC_CLEANUP_DISABLE:-0}" == "1" ]] && return 0

  olc_cleanup_log "Удаление кэшей Go/npm"

  local cleaned=0
  [[ -d /tmp/go-build ]] && { rm -rf /tmp/go-build* 2>/dev/null || true; cleaned=1; }
  find /tmp -maxdepth 1 -type d -name 'go-*' -exec rm -rf {} + 2>/dev/null || true
  [[ -d /root/.cache/go-build ]] && { rm -rf /root/.cache/go-build 2>/dev/null || true; cleaned=1; }
  [[ -d /root/.npm/_cacache ]] && { rm -rf /root/.npm/_cacache 2>/dev/null || true; cleaned=1; }
  npm cache clean --force >/dev/null 2>&1 || true

  # Go module cache can be useful for repeated builds, so keep it unless asked.
  if [[ "${OLC_CLEAN_GO_MOD_CACHE:-0}" == "1" ]]; then
    [[ -d /root/go/pkg/mod ]] && { rm -rf /root/go/pkg/mod 2>/dev/null || true; cleaned=1; }
  fi

  if [[ "$cleaned" -eq 1 ]]; then
    if declare -f olc_print_ok >/dev/null 2>&1; then
      olc_print_ok "Кэши Go/npm удалены"
    fi
  fi
}

olc_cleanup_build_caches() {
  local mode="${1:-post-build}"
  [[ "${OLC_CLEANUP_DISABLE:-0}" == "1" ]] && return 0

  # During active builds, cloned repos in /tmp must stay intact.
  if [[ "$mode" == *pre-build* || "${OLC_KEEP_BUILD_CLONES:-0}" == "1" ]]; then
    olc_cleanup_go_caches "$mode"
    return 0
  fi

  olc_cleanup_log "Удаление временных файлов сборки"

  local cleaned=0
  [[ -d /tmp/olcrtc-src ]] && { rm -rf /tmp/olcrtc-src 2>/dev/null || true; cleaned=1; }
  [[ -d /tmp/olcrtc-manager-panel ]] && { rm -rf /tmp/olcrtc-manager-panel 2>/dev/null || true; cleaned=1; }

  olc_cleanup_go_caches "$mode"

  if [[ "$cleaned" -eq 1 ]]; then
    if declare -f olc_print_ok >/dev/null 2>&1; then
      olc_print_ok "Временные файлы сборки удалены"
    fi
  fi
}

olc_cleanup_purge_caches() {
  olc_cleanup_log "Полная очистка (purge mode)"
  olc_cleanup_build_caches "purge"

  # Use find instead of glob to avoid argument list overflow
  if [[ -d /var/backups/olc-vps ]]; then
    find /var/backups/olc-vps -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tsv' -o -name '*.txt' -o -name '*.meta.txt' \) -delete 2>/dev/null || true
  fi

  apt-get clean 2>/dev/null || true
  if declare -f olc_print_ok >/dev/null 2>&1; then
    olc_print_ok "Полная очистка завершена"
  fi
}
