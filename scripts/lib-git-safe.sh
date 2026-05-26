#!/usr/bin/env bash
# Git safe.directory helpers — olcrtc-manager runs as root, repo may belong to deploy user.
# shellcheck shell=bash

olc_git_safe_register() {
  local dir="${1:-${OLC_REPO_ROOT:-/opt/Olc-cost-l}}"
  [[ -d "$dir/.git" ]] || return 0
  if git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$dir"; then
    :
  else
    git config --global --add safe.directory "$dir" 2>/dev/null || true
  fi
  local link real
  for link in /opt/olcrtc /opt/Olc-cost-l; do
    real="$(readlink -f "$link" 2>/dev/null || echo "$link")"
    [[ -d "$real/.git" ]] || continue
    if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$real"; then
      git config --global --add safe.directory "$real" 2>/dev/null || true
    fi
  done
}

# Usage: olc_git /opt/Olc-cost-l pull --ff-only origin main
olc_git() {
  local repo="$1"
  shift
  olc_git_safe_register "$repo"
  git -c "safe.directory=${repo}" -C "$repo" "$@"
}
