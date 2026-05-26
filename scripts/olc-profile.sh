#!/usr/bin/env bash
# Manage deploy profile (which components olc-update runs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-/opt/Olc-cost-l}"
[[ -d "$REPO_ROOT/.git" ]] || REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib-deploy-profile.sh
source "$SCRIPT_DIR/lib-deploy-profile.sh"

usage() {
  cat <<EOF
Usage:
  olc-profile show                 # current profile JSON
  olc-profile list                 # available template ids
  olc-profile set <profile-id>     # install template (ru-full, foreign-minimal, …)
  olc-profile write              # save profile from current env/flags

File: $OLCRTC_DEPLOY_PROFILE
EOF
}

need_root() {
  [[ "$(id -u)" -eq 0 ]] || exec sudo -E bash "$0" "$@"
}

cmd="${1:-show}"
shift || true

case "$cmd" in
  show|-s)
    need_root
    profile_show || exit 1
    ;;
  list|-l)
    profile_list_templates
    ;;
  set)
    need_root
    id="${1:-}"
    [[ -n "$id" ]] || { echo "usage: olc-profile set <id>" >&2; exit 1; }
    profile_install_template "$id"
    profile_apply_env
  profile_show
    ;;
  write)
    need_root
    profile_from_flags
    profile_show
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "unknown: $cmd" >&2
    usage
    exit 1
    ;;
esac
