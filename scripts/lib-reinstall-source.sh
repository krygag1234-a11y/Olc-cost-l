#!/usr/bin/env bash

olc_reinstall_restore_bundle() {
  local bundle="$1"
  local install_dir="$2"
  local branch="$3"
  local expected_commit="$4"
  local origin_url="$5"

  [[ -f "$bundle" ]] || return 1
  [[ -n "$branch" && -n "$expected_commit" && -n "$origin_url" ]] || return 1
  [[ ! -e "$install_dir" ]] || return 1

  git clone --quiet --branch "$branch" "$bundle" "$install_dir"
  [[ "$(git -C "$install_dir" rev-parse HEAD)" == "$expected_commit" ]] || return 1

  # A bundle is only a transport snapshot. Future olc-update runs must follow
  # the canonical repository instead of the temporary reinstall workdir.
  git -C "$install_dir" remote set-url origin "$origin_url"
  [[ "$(git -C "$install_dir" remote get-url origin)" == "$origin_url" ]]
}
