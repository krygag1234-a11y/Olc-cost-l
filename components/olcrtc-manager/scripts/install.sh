#!/usr/bin/env bash
set -euo pipefail

random_hex() {
	local bytes="${1:-16}"
	od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

random_port() {
	local raw port
	for _ in $(seq 1 20); do
		raw="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
		port=$((20000 + raw % 40000))
		if ! ss -ltn "( sport = :$port )" 2>/dev/null | grep -q ":$port"; then
			printf '%s\n' "$port"
			return
		fi
	done
	printf '%s\n' 8888
}

PANEL_REPO="${PANEL_REPO:-https://github.com/BigDaddy3334/olcrtc-manager-panel.git}"
PANEL_REF="${PANEL_REF:-main}"
OLCRTC_REPO="${OLCRTC_REPO:-https://github.com/openlibrecommunity/olcrtc.git}"
OLCRTC_REF="${OLCRTC_REF:-master}"
GO_VERSION="${GO_VERSION:-1.25.0}"
PANEL_ADDR="${PANEL_ADDR:-127.0.0.1}"
PANEL_PORT="${PANEL_PORT:-$(random_port)}"
PANEL_ADMIN_PATH="${PANEL_ADMIN_PATH:-${OLCRTC_MANAGER_ADMIN_PATH:-/admin-$(random_hex 4)}}"
case "$PANEL_ADMIN_PATH" in
	/*) ;;
	*) PANEL_ADMIN_PATH="/$PANEL_ADMIN_PATH" ;;
esac
INSTALL_SRC_DIR="${INSTALL_SRC_DIR:-/opt/olcrtc-manager-src}"
CONFIG_DIR="${CONFIG_DIR:-/etc/olcrtc-manager}"
CONFIG_PATH="${CONFIG_PATH:-$CONFIG_DIR/config.json}"
PANEL_ENV_PATH="${PANEL_ENV_PATH:-$CONFIG_DIR/panel.env}"
PANEL_TLS="${PANEL_TLS:-1}"
TLS_CERT_PATH="${TLS_CERT_PATH:-$CONFIG_DIR/tls.crt}"
TLS_KEY_PATH="${TLS_KEY_PATH:-$CONFIG_DIR/tls.key}"
PANEL_CERT_IP="${PANEL_CERT_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
PANEL_PUBLIC_HOST="${PANEL_PUBLIC_HOST:-$PANEL_CERT_IP}"
GENERATED_PANEL_ENV=0
GENERATED_ADMIN_USER=""
GENERATED_ADMIN_PASS=""
PANEL_SUPPORTS_ADMIN_PATH=1
PANEL_SUPPORTS_TLS=1
DISPLAY_SCHEME="http"
DISPLAY_ADMIN_PATH="$PANEL_ADMIN_PATH"
DISPLAY_HOST="$PANEL_ADDR"
if [ "$DISPLAY_HOST" = "0.0.0.0" ] || [ "$DISPLAY_HOST" = "::" ]; then
	DISPLAY_HOST="${PANEL_PUBLIC_HOST:-$DISPLAY_HOST}"
fi

log() {
	printf '[olcrtc-manager] %s\n' "$*"
}

die() {
	printf '[olcrtc-manager] ERROR: %s\n' "$*" >&2
	exit 1
}

need_root() {
	if [ "$(id -u)" -ne 0 ]; then
		die "run as root: curl -fsSL .../scripts/install.sh | sudo bash"
	fi
}

install_packages() {
	if command -v apt-get >/dev/null 2>&1; then
		export DEBIAN_FRONTEND=noninteractive
		apt-get update
		apt-get install -y --no-install-recommends ca-certificates curl git tar xz-utils iproute2 iptables openssl
		return
	fi
	die "unsupported OS: this installer currently supports apt-based Linux distributions"
}

go_arch() {
	case "$(uname -m)" in
		x86_64|amd64) echo "amd64" ;;
		aarch64|arm64) echo "arm64" ;;
		*) die "unsupported CPU architecture: $(uname -m)" ;;
	esac
}

go_version_ok() {
	command -v go >/dev/null 2>&1 || return 1
	local current
	current="$(go env GOVERSION | sed 's/^go//')"
	[ "$(printf '%s\n%s\n' "$GO_VERSION" "$current" | sort -V | head -n1)" = "$GO_VERSION" ]
}

install_go() {
	if go_version_ok; then
		log "Go $(go env GOVERSION) found"
		return
	fi

	local arch archive url tmp
	arch="$(go_arch)"
	archive="go${GO_VERSION}.linux-${arch}.tar.gz"
	url="https://go.dev/dl/${archive}"
	tmp="/tmp/${archive}"

	log "installing Go ${GO_VERSION}"
	curl -fsSL "$url" -o "$tmp"
	rm -rf /usr/local/go
	tar -C /usr/local -xzf "$tmp"
	ln -sf /usr/local/go/bin/go /usr/local/bin/go
	ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
}

clone_repo() {
	local repo="$1" ref="$2" dest="$3"
	rm -rf "$dest"
	git clone --depth 1 --branch "$ref" "$repo" "$dest"
}

build_olcrtc() {
	local src="$1"
	log "building olcrtc"
	(cd "$src" && CGO_ENABLED=0 go build -o /tmp/olcrtc ./cmd/olcrtc)
	install -m 0755 /tmp/olcrtc /usr/local/bin/olcrtc
}

build_manager() {
	local src="$1"
	log "building olcrtc-manager"
	if [ ! -f "$src/cmd/olcrtc-manager/web/dist/index.html" ]; then
		die "frontend bundle is missing in repository; build assets before publishing installer"
	fi
	(cd "$src" && CGO_ENABLED=0 go build -o /tmp/olcrtc-manager ./cmd/olcrtc-manager)
	install -m 0755 /tmp/olcrtc-manager /usr/local/bin/olcrtc-manager
}

detect_manager_features() {
	if grep -aq "OLCRTC_MANAGER_ADMIN_PATH" /usr/local/bin/olcrtc-manager; then
		PANEL_SUPPORTS_ADMIN_PATH=1
	else
		PANEL_SUPPORTS_ADMIN_PATH=0
		PANEL_ADMIN_PATH="/admin"
		DISPLAY_ADMIN_PATH="/admin"
		log "built manager does not support custom admin path; using /admin"
	fi

	if grep -aq "OLCRTC_MANAGER_TLS_CERT" /usr/local/bin/olcrtc-manager && grep -aq "OLCRTC_MANAGER_TLS_KEY" /usr/local/bin/olcrtc-manager; then
		PANEL_SUPPORTS_TLS=1
	else
		PANEL_SUPPORTS_TLS=0
		PANEL_TLS=0
		DISPLAY_SCHEME="http"
		log "built manager does not support built-in TLS; using HTTP"
	fi
}

write_config_if_missing() {
	install -d -m 0755 "$CONFIG_DIR"
	install -d -m 0700 "$CONFIG_DIR/backups"

	if [ -f "$CONFIG_PATH" ]; then
		log "keeping existing config: $CONFIG_PATH"
		return
	fi

	log "creating initial config without rooms"

	cat > "$CONFIG_PATH" <<EOF
{
  "version": 1,
  "name": "OlcRTC VPS",
  "port": $PANEL_PORT,
  "clients": []
}
EOF
	chmod 0600 "$CONFIG_PATH"
	log "created config: $CONFIG_PATH"
}

write_tls_cert_if_missing() {
	if [ "$PANEL_TLS" != "1" ]; then
		return
	fi
	install -d -m 0755 "$CONFIG_DIR"
	if [ -f "$TLS_CERT_PATH" ] && [ -f "$TLS_KEY_PATH" ]; then
		log "keeping existing TLS certificate: $TLS_CERT_PATH"
		DISPLAY_SCHEME="https"
		return
	fi

	local san
	san="DNS:localhost"
	if [ -n "$PANEL_CERT_IP" ]; then
		san="IP:${PANEL_CERT_IP},DNS:localhost"
	fi
	log "creating self-signed TLS certificate: $TLS_CERT_PATH"
	openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 825 \
		-keyout "$TLS_KEY_PATH" \
		-out "$TLS_CERT_PATH" \
		-subj "/CN=olcrtc-manager" \
		-addext "subjectAltName=${san}" >/dev/null 2>&1
	chmod 0600 "$TLS_KEY_PATH"
	chmod 0644 "$TLS_CERT_PATH"
	DISPLAY_SCHEME="https"
}

read_env_value() {
	local key="$1" file="$2" value
	value="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
	value="${value#\'}"
	value="${value%\'}"
	printf '%s\n' "$value"
}

write_panel_env_if_missing() {
	install -d -m 0755 "$CONFIG_DIR"
	if [ -f "$PANEL_ENV_PATH" ]; then
		log "keeping existing panel env: $PANEL_ENV_PATH"
		if [ "$PANEL_SUPPORTS_ADMIN_PATH" = "1" ]; then
			DISPLAY_ADMIN_PATH="$(read_env_value OLCRTC_MANAGER_ADMIN_PATH "$PANEL_ENV_PATH")"
			DISPLAY_ADMIN_PATH="${DISPLAY_ADMIN_PATH:-/admin}"
		else
			DISPLAY_ADMIN_PATH="/admin"
		fi
		if [ "$PANEL_SUPPORTS_TLS" = "1" ] && [ -n "$(read_env_value OLCRTC_MANAGER_TLS_CERT "$PANEL_ENV_PATH")" ]; then
			DISPLAY_SCHEME="https"
		fi
		return
	fi

	GENERATED_PANEL_ENV=1
	GENERATED_ADMIN_USER="${PANEL_ADMIN_USER:-admin$(random_hex 3)}"
	GENERATED_ADMIN_PASS="${PANEL_ADMIN_PASS:-$(random_hex 16)}"
	cat > "$PANEL_ENV_PATH" <<EOF
OLCRTC_MANAGER_USER='$GENERATED_ADMIN_USER'
OLCRTC_MANAGER_PASS='$GENERATED_ADMIN_PASS'
EOF
	if [ "$PANEL_SUPPORTS_ADMIN_PATH" = "1" ]; then
		cat >> "$PANEL_ENV_PATH" <<EOF
OLCRTC_MANAGER_ADMIN_PATH='$PANEL_ADMIN_PATH'
EOF
	fi
	if [ "$PANEL_SUPPORTS_TLS" = "1" ] && [ "$PANEL_TLS" = "1" ]; then
		cat >> "$PANEL_ENV_PATH" <<EOF
OLCRTC_MANAGER_TLS_CERT='$TLS_CERT_PATH'
OLCRTC_MANAGER_TLS_KEY='$TLS_KEY_PATH'
EOF
	fi
	chmod 0600 "$PANEL_ENV_PATH"
	log "created panel env: $PANEL_ENV_PATH"
}

install_service() {
	log "installing systemd service"
	cat > /etc/systemd/system/olcrtc-manager.service <<EOF
[Unit]
Description=OlcRTC Manager Panel
Documentation=https://github.com/BigDaddy3334/olcrtc-manager-panel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=OLCRTC_PATH=/usr/local/bin/olcrtc
Environment=OLCRTC_MANAGER_ADDR=$PANEL_ADDR
EnvironmentFile=-$PANEL_ENV_PATH
ExecStart=/usr/local/bin/olcrtc-manager -config $CONFIG_PATH
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
KillSignal=SIGTERM
TimeoutStopSec=10s

[Install]
WantedBy=multi-user.target
EOF
	systemctl daemon-reload
	systemctl enable --now olcrtc-manager
}

sync_sources() {
	local src="$1"
	rm -rf "$INSTALL_SRC_DIR"
	mkdir -p "$INSTALL_SRC_DIR"
	tar --exclude='.git' --exclude='node_modules' -C "$src" -cf - . | tar -C "$INSTALL_SRC_DIR" -xf -
}

main() {
	need_root
	install_packages
	install_go

	local work panel_src olcrtc_src
	work="$(mktemp -d /tmp/olcrtc-manager-install.XXXXXX)"
	trap 'rm -rf "${work:-}"' EXIT
	panel_src="$work/panel"
	olcrtc_src="$work/olcrtc"

	clone_repo "$OLCRTC_REPO" "$OLCRTC_REF" "$olcrtc_src"
	clone_repo "$PANEL_REPO" "$PANEL_REF" "$panel_src"
	build_olcrtc "$olcrtc_src"
	build_manager "$panel_src"
	detect_manager_features
	write_config_if_missing
	write_tls_cert_if_missing
	write_panel_env_if_missing
	install_service
	sync_sources "$panel_src"

	log "done"
	log "service: systemctl status olcrtc-manager"
	log "Access URL: ${DISPLAY_SCHEME}://${DISPLAY_HOST}:${PANEL_PORT}${DISPLAY_ADMIN_PATH}"
	log "WebBasePath: ${DISPLAY_ADMIN_PATH#/}"
	if [ "$GENERATED_PANEL_ENV" = "1" ]; then
		log "Username: $GENERATED_ADMIN_USER"
		log "Password: $GENERATED_ADMIN_PASS"
	fi
	if [ "$PANEL_ADDR" = "127.0.0.1" ]; then
		log "the panel listens locally; expose it with nginx or reinstall with PANEL_ADDR=0.0.0.0"
	fi
	if [ "$PANEL_TLS" = "1" ]; then
		log "TLS uses a self-signed certificate by default; browsers may ask you to accept it."
	fi
}

main "$@"
