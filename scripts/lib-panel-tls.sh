#!/usr/bin/env bash
# Panel TLS helpers: self-signed or short-lived public IP certificates.
# shellcheck shell=bash

olc_panel_public_ip() {
  local candidate="${PANEL_CERT_IP:-}"
  if [[ -z "$candidate" ]] && command -v curl >/dev/null 2>&1; then
    candidate="$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "$candidate" ]] && command -v curl >/dev/null 2>&1; then
    candidate="$(curl -4 -fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null || true)"
  fi
  candidate="$(printf '%s' "$candidate" | tr -d '[:space:]')"
  python3 - "$candidate" <<'PY'
import ipaddress, sys
try:
    ip = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
if ip.version != 4 or not ip.is_global:
    raise SystemExit(1)
print(ip)
PY
}

olc_panel_certbot_command() {
  local candidate version
  for candidate in /opt/olc-certbot/bin/certbot "$(command -v certbot 2>/dev/null || true)"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    version="$("$candidate" --version 2>/dev/null | awk '{print $2}')"
    if python3 - "$version" <<'PY'
import sys
parts = []
for bit in sys.argv[1].split(".")[:2]:
    try: parts.append(int(bit))
    except ValueError: parts.append(0)
while len(parts) < 2: parts.append(0)
raise SystemExit(0 if tuple(parts) >= (5, 4) else 1)
PY
    then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

olc_panel_install_certbot() {
  local certbot
  if certbot="$(olc_panel_certbot_command)"; then printf '%s\n' "$certbot"; return 0; fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >&2
  apt-get install -y -qq python3-venv python3-pip ca-certificates curl >&2
  if [[ ! -x /opt/olc-certbot/bin/python ]]; then python3 -m venv /opt/olc-certbot >&2; fi
  /opt/olc-certbot/bin/python -m pip install --quiet --upgrade pip >&2
  /opt/olc-certbot/bin/python -m pip install --quiet --upgrade 'certbot>=5.4,<6' >&2
  certbot="$(olc_panel_certbot_command)" || { echo "Certbot 5.4+ не установлен" >&2; return 1; }
  printf '%s\n' "$certbot"
}

olc_panel_setup_certbot_timer() {
  local certbot="$1"
  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
  cat >/etc/letsencrypt/renewal-hooks/deploy/olc-manager-restart <<'HOOK'
#!/usr/bin/env bash
systemctl try-restart olcrtc-manager.service
HOOK
  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/olc-manager-restart
  cat >/etc/systemd/system/olc-certbot-renew.service <<EOF_SERVICE
[Unit]
Description=Renew short-lived Let's Encrypt certificates used by OlcRTC Manager
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=$certbot renew --quiet
EOF_SERVICE
  cat >/etc/systemd/system/olc-certbot-renew.timer <<'EOF_TIMER'
[Unit]
Description=Check OlcRTC Manager IP certificate renewal every 6 hours
[Timer]
OnCalendar=*-*-* 00/6:17:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
EOF_TIMER
  systemctl daemon-reload
  systemctl enable --now olc-certbot-renew.timer >/dev/null
}

olc_panel_issue_letsencrypt_ip() {
  local public_ip certbot cert_dir
  public_ip="$(olc_panel_public_ip)" || { echo "Не найден публичный глобальный IPv4. Можно задать PANEL_CERT_IP явно." >&2; return 1; }
  local -a authenticator_args=(--standalone)
  if command -v ss >/dev/null 2>&1 && ss -H -ltn 'sport = :80' 2>/dev/null | grep -q .; then
    local acme_webroot="${PANEL_ACME_WEBROOT:-/var/www/html}"
    if [[ -d "$acme_webroot" ]] && grep -RqsE 'location[[:space:]]+/?\.well-known/acme-challenge' /etc/nginx /etc/apache2 2>/dev/null; then
      authenticator_args=(--webroot --webroot-path "$acme_webroot")
      echo "TCP-порт 80 занят веб-сервером; используем существующий ACME webroot: $acme_webroot" >&2
    else
      echo "TCP-порт 80 занят, а совместимый ACME webroot не найден. Задайте PANEL_ACME_WEBROOT." >&2
      return 1
    fi
  fi
  certbot="$(olc_panel_install_certbot)" || return 1
  "$certbot" certonly \
    "${authenticator_args[@]}" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --preferred-profile shortlived \
    --ip-address "$public_ip" \
    --cert-name "$public_ip" \
    --keep-until-expiring
  cert_dir="/etc/letsencrypt/live/$public_ip"
  [[ -s "$cert_dir/fullchain.pem" && -s "$cert_dir/privkey.pem" ]] || { echo "Certbot завершился без ожидаемых файлов сертификата для $public_ip" >&2; return 1; }
  olc_panel_setup_certbot_timer "$certbot"
  PANEL_TLS_CERT_RESULT="$cert_dir/fullchain.pem"
  PANEL_TLS_KEY_RESULT="$cert_dir/privkey.pem"
  PANEL_TLS_IP_RESULT="$public_ip"
  export PANEL_TLS_CERT_RESULT PANEL_TLS_KEY_RESULT PANEL_TLS_IP_RESULT
}
