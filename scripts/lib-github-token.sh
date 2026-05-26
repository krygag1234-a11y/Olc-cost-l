#!/usr/bin/env bash
# Load GITHUB_TOKEN from repo .env (gitignored). Do not ask the user for a token.
set -euo pipefail

_olc_repo_root() {
  local d
  d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  echo "$d"
}

olc_load_github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    return 0
  fi
  local root envf
  root="${OLC_REPO_ROOT:-$(_olc_repo_root)}"
  envf="$root/.env"
  if [[ -f "$envf" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$envf"
    set +a
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]] && [[ -n "${GH_TOKEN:-}" ]]; then
    export GITHUB_TOKEN="$GH_TOKEN"
  fi
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "missing GITHUB_TOKEN: create $envf from .env.example" >&2
    return 1
  fi
}

olc_git_push_url() {
  local slug="${1:-krygag1234-a11y/Olc-cost-l}"
  olc_load_github_token || return 1
  echo "https://krygag1234-a11y:${GITHUB_TOKEN}@github.com/${slug}.git"
}
