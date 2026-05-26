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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"
# shellcheck source=lib-git-safe.sh
source "$SCRIPT_DIR/lib-git-safe.sh"

main() {
  need_root "$@"
  local repo profile_arg=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --show-profile) profile_show; exit 0 ;;
      --profile) profile_arg=(--profile) ;;
    esac
  done
  repo="$(detect_repo)" || {
    echo "Olc-cost-l repo not found. Install first, then run: olc-update" >&2
    exit 1
  }
  cd "$repo"
  export OLC_REPO_ROOT="$repo"
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
