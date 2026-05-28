#!/usr/bin/env bash
# Shared cleanup for build/runtime caches left by Olc-cost-l scripts.
[[ -n "${_OLC_CACHE_CLEANUP_LOADED:-}" ]] && return 0
_OLC_CACHE_CLEANUP_LOADED=1

olc_cleanup_log() {
  echo "[olc-cleanup] $*" >&2
}

olc_cleanup_build_caches() {
  local mode="${1:-post-build}"
  [[ "${OLC_CLEANUP_DISABLE:-0}" == "1" ]] && return 0

  olc_cleanup_log "${mode}: remove temporary build caches"
  rm -rf /tmp/olcrtc-src /tmp/olcrtc-manager-panel /tmp/go-build* 2>/dev/null || true
  rm -rf /root/.cache/go-build /root/.npm/_cacache 2>/dev/null || true
  npm cache clean --force >/dev/null 2>&1 || true

  # Go module cache can be useful for repeated builds, so keep it unless asked.
  if [[ "${OLC_CLEAN_GO_MOD_CACHE:-0}" == "1" ]]; then
    rm -rf /root/go/pkg/mod 2>/dev/null || true
  fi
}

olc_cleanup_purge_caches() {
  olc_cleanup_build_caches "purge"
  rm -rf /var/backups/olc-vps/*.tar.gz /var/backups/olc-vps/*.tsv /var/backups/olc-vps/*.txt 2>/dev/null || true
  apt-get clean 2>/dev/null || true
}
