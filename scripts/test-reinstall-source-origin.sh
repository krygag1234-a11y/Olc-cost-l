#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-reinstall-source.sh
source "$SCRIPT_DIR/lib-reinstall-source.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

source_repo="$tmp/source"
bundle="$tmp/source.bundle"
restored="$tmp/restored"
expected_origin="https://example.invalid/owner/project.git"

git init -q -b main "$source_repo"
git -C "$source_repo" config user.name test
git -C "$source_repo" config user.email test@example.invalid
printf 'vendored\n' >"$source_repo/install.sh"
git -C "$source_repo" add install.sh
git -C "$source_repo" commit -qm initial
expected_commit="$(git -C "$source_repo" rev-parse HEAD)"
git -C "$source_repo" bundle create "$bundle" refs/heads/main

olc_reinstall_restore_bundle \
  "$bundle" "$restored" main "$expected_commit" "$expected_origin"

[[ "$(git -C "$restored" rev-parse HEAD)" == "$expected_commit" ]]
[[ "$(git -C "$restored" remote get-url origin)" == "$expected_origin" ]]

if olc_reinstall_restore_bundle \
  "$bundle" "$restored" main "$expected_commit" "$expected_origin"; then
  echo "expected restore into an existing path to fail" >&2
  exit 1
fi

echo "reinstall-source-origin: PASS"
