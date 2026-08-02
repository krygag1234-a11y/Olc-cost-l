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
  apt-get update -qq
  apt-get install -y -qq python3-venv python3-pip ca-certificates curl
  if [[ ! -x /opt/olc-certbot/bin/python ]]; then python3 -m venv /opt/olc-certbot; fi
  /opt/olc-certbot/bin/python -m pip install --quiet --upgrade pip
  /opt/olc-certbot/bin/python -m pip install --quiet --upgrade 'certbot>=5.4,<6'
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
  if command -v ss >/dev/null 2>&1 && ss -H -ltn 'sport = :80' 2>/dev/null | grep -q .; then
    echo "TCP-порт 80 уже занят; standalone-проверка Let's Encrypt не сможет запуститься." >&2
    return 1
  fi
  certbot="$(olc_panel_install_certbot)" || return 1
  "$certbot" certonly \
    --standalone \
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
