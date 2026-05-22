# Split tunnel (RU VPS) — как работает в 2026

## Проблема «404 Not Found nginx»

Старый подход: резолвить CDN в **/32 IP** и класть в `direct-all.txt`.  
CDN меняет edge, один IP = чужой nginx → **404** при прямом подключении.

## Правильный подход (сейчас)

| Слой | Файл | Логика |
|------|------|--------|
| **Домены** | `/var/lib/olcrtc/ru-direct-domains.txt` | `.ru`, `.okko.tv`, `.ivi.ru`, … → **всегда direct** (VPS резолвит в RU) |
| **GeoIP RU** | `/var/lib/olcrtc/ru-cidrs.txt` | IP из российских диапазонов → direct |
| **Остальное** | — | Tor exit (`127.0.0.1:9050`) |

Патч olcrtc: `direct_domains_file` + `direct_cidrs_file` в YAML.

## Установка / обновление

```bash
sudo /opt/Olc-cost-l/scripts/setup-split-ru.sh
sudo systemctl restart olcrtc-manager
```

В `panel.env`:

```bash
OLCRTC_DIRECT_CIDRS=/var/lib/olcrtc/ru-cidrs.txt
OLCRTC_DIRECT_DOMAINS=/var/lib/olcrtc/ru-direct-domains.txt
```

## Опционально (не рекомендуется)

CDN /32 снова: `OLCRTC_INCLUDE_CDN_IPS=1 setup-split-ru.sh` — может вернуть 404.

## Иностранный VPS

`--no-tor` / `--foreign` — split-скрипты **не запускаются**.

## Ссылки

- [GrimbirdUsers/ru-routing-dat](https://github.com/GrimbirdUsers/ru-routing-dat) — geosite/geoip для Xray/Happ (идея списков доменов)
- [RIA: кинотеатры и VPN](https://ria.ru/20260417/vpn-2087467666.html) — проверка «не RU IP» на CDN (2026)
