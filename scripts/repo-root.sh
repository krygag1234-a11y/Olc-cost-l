#!/usr/bin/env bash
# Resolve repository root (Olc-cost-l checkout).
[[ -n "${_OLC_REPO_ROOT_LOADED:-}" ]] && return 0
_OLC_REPO_ROOT_LOADED=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PATCH_DIR="${PATCH_DIR:-$REPO_ROOT/patches}"
INSTALL_DIR="${OLC_INSTALL_DIR:-/opt/Olc-cost-l}"
