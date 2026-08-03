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


# Print only changes that are not maintained automatically by updater jobs.
olc_git_unmanaged_dirty() {
  local repo="${1:-${OLC_REPO_ROOT:-/opt/Olc-cost-l}}"
  local line path committed normalized_current normalized_committed
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    path="${line:3}"
    case "$path" in
      data/zapret-community-excludes/*|data/zapret4rocket/*)
        continue
        ;;
      data/upstream-pins.json)
        committed="$(git -C "$repo" show HEAD:data/upstream-pins.json 2>/dev/null || true)"
        normalized_committed="$(printf '%s' "$committed" | jq -cS 'del(.zapret4rocket.pinned_sha, .zapret4rocket.upstream_head, .zapret4rocket.last_sync, .zapret4rocket.last_apply_ok)' 2>/dev/null || true)"
        normalized_current="$(jq -cS 'del(.zapret4rocket.pinned_sha, .zapret4rocket.upstream_head, .zapret4rocket.last_sync, .zapret4rocket.last_apply_ok)' "$repo/data/upstream-pins.json" 2>/dev/null || true)"
        if [[ -n "$normalized_committed" && "$normalized_current" == "$normalized_committed" ]]; then
          continue
        fi
        ;;
    esac
    printf '%s\n' "$path"
  done < <(git -C "$repo" status --porcelain 2>/dev/null || true)
}
