# Функции проверки компонентов для режима INCREMENTAL
check_packages_installed() {
  command -v git >/dev/null 2>&1 && \
  command -v go >/dev/null 2>&1 && \
  command -v npm >/dev/null 2>&1
}

check_binaries_built() {
  [[ -x /usr/local/bin/olcrtc ]] && \
  [[ -x /usr/local/bin/olcrtc-manager ]]
}

check_tor_installed() {
  command -v tor >/dev/null 2>&1 && \
  systemctl is-active tor@default >/dev/null 2>&1
}

check_zapret_installed() {
  [[ -x /opt/zapret/nfq/nfqws ]] && \
  pidof nfqws >/dev/null 2>&1
}

check_split_configured() {
  [[ -f /var/lib/olcrtc/ru-direct-domains.txt ]] && \
  [[ -s /var/lib/olcrtc/ru-direct-domains.txt ]]
}
