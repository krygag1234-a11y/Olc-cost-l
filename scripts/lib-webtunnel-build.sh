#!/usr/bin/env bash
# Shared webtunnel-client build (optional PT). obfs4/snowflake work without it.
# shellcheck shell=bash

webtunnel_client_ready() {
  [[ -x /usr/bin/webtunnel-client ]] || [[ -x /usr/local/bin/webtunnel-client ]]
}

webtunnel_client_path() {
  if [[ -x /usr/bin/webtunnel-client ]]; then
    echo /usr/bin/webtunnel-client
  elif [[ -x /usr/local/bin/webtunnel-client ]]; then
    echo /usr/local/bin/webtunnel-client
  fi
}

# BRIDGE_TYPES without webtunnel when binary is missing.
effective_bridge_types() {
  local want="${1:-${BRIDGE_TYPES:-webtunnel,obfs4}}"
  if webtunnel_client_ready; then
    echo "$want"
    return 0
  fi
  local out=() t
  IFS=',' read -r -a parts <<<"$want"
  for t in "${parts[@]}"; do
    t="${t// /}"
    [[ -z "$t" ]] && continue
    [[ "$t" == "webtunnel" ]] && continue
    out+=("$t")
  done
  if ((${#out[@]} == 0)); then
    echo obfs4
  else
    local IFS=,
    echo "${out[*]}"
  fi
}

_webtunnel_fetch_tree() {
  local dest="$1"
  local git_urls=(
    "https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel.git"
  )
  local archive_urls=(
    "https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/webtunnel/-/archive/master/webtunnel-master.tar.gz"
  )
  local git_cfg=(
    -c http.lowSpeedLimit=1000
    -c http.lowSpeedTime=120
    -c http.postBuffer=524288000
  )
  local url attempt

  rm -rf "$dest"
  for url in "${git_urls[@]}"; do
    for attempt in 1 2 3; do
      if timeout 180 git "${git_cfg[@]}" clone --depth 1 "$url" "$dest" 2>/dev/null; then
        return 0
      fi
      sleep $((attempt * 4))
    done
  done

  local arc tmpd="/tmp/webtunnel-archive-$$"
  rm -rf "$tmpd"
  mkdir -p "$tmpd"
  for url in "${archive_urls[@]}"; do
    if curl -fsSL --connect-timeout 25 --max-time 300 -o "$tmpd/webtunnel.tar.gz" "$url" 2>/dev/null; then
      if tar -xzf "$tmpd/webtunnel.tar.gz" -C "$tmpd" 2>/dev/null; then
        local extracted
        extracted="$(find "$tmpd" -maxdepth 1 -type d -name 'webtunnel-*' | head -1)"
        if [[ -n "$extracted" && -d "$extracted/client" ]]; then
          mv "$extracted" "$dest"
          rm -rf "$tmpd"
          return 0
        fi
      fi
    fi
  done
  rm -rf "$tmpd"
  return 1
}

# Build /usr/bin/webtunnel-client. Returns 0 on success.
build_webtunnel_client() {
  local log_fn="${1:-echo}"
  if [[ "${OLCRTC_SKIP_WEBTUNNEL:-0}" == "1" ]]; then
    "$log_fn" "[webtunnel] skip (OLCRTC_SKIP_WEBTUNNEL=1)"
    return 1
  fi
  if webtunnel_client_ready; then
    "$log_fn" "[webtunnel] already installed: $(webtunnel_client_path)"
    return 0
  fi
  command -v go >/dev/null 2>&1 || return 1
  export PATH="/usr/local/go/bin:${PATH:-}"
  export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

  local wt="/tmp/webtunnel-build-$$"
  "$log_fn" "[webtunnel] fetching sources (gitlab; may take up to 3 min)…"
  if ! _webtunnel_fetch_tree "$wt"; then
    "$log_fn" "[webtunnel] WARN: fetch failed (SSL timeout?) — Tor will use obfs4/snowflake only"
    "$log_fn" "[webtunnel] retry later: ${OLC_REPO_ROOT:-/opt/Olc-cost-l}/scripts/install-tor-pluggable-transports.sh"
    rm -rf "$wt"
    return 1
  fi
  if ! (cd "$wt/client" && go build -o /usr/bin/webtunnel-client .); then
    "$log_fn" "[webtunnel] WARN: go build failed — using obfs4 only"
    rm -rf "$wt"
    return 1
  fi
  rm -rf "$wt"
  chmod 755 /usr/bin/webtunnel-client
  "$log_fn" "[webtunnel] installed /usr/bin/webtunnel-client"
  return 0
}
