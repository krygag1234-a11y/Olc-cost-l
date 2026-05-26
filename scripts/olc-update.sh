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

main() {
  need_root "$@"
  local repo
  repo="$(detect_repo)" || {
    echo "Olc-cost-l repo not found. Install first, then run: olc-update" >&2
    exit 1
  }
  cd "$repo"
  git pull --ff-only origin main
  bash scripts/agent-bootstrap.sh --update "$@"
}

main "$@"
