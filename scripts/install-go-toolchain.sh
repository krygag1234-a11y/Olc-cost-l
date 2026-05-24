#!/usr/bin/env bash
# Install modern Go to /usr/local/go when distro package is too old for upstream olcrtc (go 1.26 in go.mod).
set -euo pipefail

GO_VERSION="${OLC_GO_VERSION:-1.23.6}"
INSTALL_DIR="/usr/local/go"

need_install() {
  if [[ ! -x "$INSTALL_DIR/bin/go" ]]; then
    return 0
  fi
  # olcrtc needs toolchain >= 1.22; go.mod may request 1.26 via GOTOOLCHAIN
  local v
  v="$("$INSTALL_DIR/bin/go" version 2>/dev/null | awk '{print $3}' | sed 's/go//')"
  [[ "${v%%.*}" -lt 1 ]] && return 0
  return 1
}

if need_install; then
  echo "[install-go] installing Go ${GO_VERSION} → ${INSTALL_DIR}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o "$tmp/go.tgz"
  rm -rf "$INSTALL_DIR"
  tar -C /usr/local -xzf "$tmp/go.tgz"
  echo "[install-go] $(/usr/local/go/bin/go version)"
else
  echo "[install-go] $(/usr/local/go/bin/go version) (ok)"
fi

# Prefer modern Go for builds in this session and systemd units
export PATH="/usr/local/go/bin:${PATH}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

if ! grep -qF '/usr/local/go/bin' /etc/profile.d/olc-go.sh 2>/dev/null; then
  echo 'export PATH="/usr/local/go/bin:$PATH"' >/etc/profile.d/olc-go.sh
  echo 'export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"' >>/etc/profile.d/olc-go.sh
  chmod 0644 /etc/profile.d/olc-go.sh
fi
