# Split tunnel (RU VPS) — как работает в 2026

## Проблема «404 Not Found nginx»

Старый подход: резолвить CDN в **/32 IP** и класть в `direct-all.txt`.  
CDN меняет edge, один IP = чужой nginx → **404** при прямом подключении.

## Правильный подход (сейчас)

| Слой | Источник | Логика |
|------|----------|--------|
| **Встроено в olcrtc** | код `MatchBuiltinRU` | **Любой** хост `*.ru`, `*.su`, `*.рф`, IDN TLD → direct без записи в файле |
| **Домены (geosite)** | `ru-direct-domains.txt` | okko, vk, alloha, voidboost, … из [ru-routing-dat](https://github.com/GrimbirdUsers/ru-routing-dat) |
| **GeoIP RU** | `ru-cidrs.txt` | Только если клиент подключается к **литеральному IP** (не по DNS→CIDR) |
| **Embed CDN** | `data/ru-embed-balancers.txt` | kinobalancer: bhcesh, ortified, lumex, rewall, kodik, … |
| **Остальное** | — | Tor exit (`127.0.0.1:9050`) |

**Важно:** резолв чужого домена в RU IP и direct на этот IP давал **404 nginx** (чужой vhost на shared CDN). DNS→CIDR отключён с 2026-05-22.

Пример: `doktor-ktto-lordfilm.ru` — зеркало Lordfilm — **всегда direct** по суффиксу `.ru`.  
Плеер может тянуть embed с `alloha.tv` / `voidboost.*` — они в geosite-списке балансеров (не `.ru`, но нужен RU IP VPS).

Патч olcrtc: `direct_domains_file` + `direct_cidrs_file` в YAML.

## Установка / обновление

```bash
sudo chmod +x /opt/Olc-cost-l/scripts/*.sh
sudo /opt/Olc-cost-l/scripts/setup-split-ru.sh
sudo /opt/Olc-cost-l/scripts/apply-olcrtc-patches.sh
sudo systemctl restart olcrtc-manager
```

В `panel.env`:

```bash
OLCRTC_DIRECT_CIDRS=/var/lib/olcrtc/ru-cidrs.txt
OLCRTC_DIRECT_DOMAINS=/var/lib/olcrtc/ru-direct-domains.txt
OLCRTC_BLOCKED_TOR_DOMAINS=/var/lib/olcrtc/ru-blocked-tor-domains.txt
```

## Добавить хосты с конкретной страницы (плеер)

```bash
sudo /opt/Olc-cost-l/scripts/discover-page-hosts.sh 'https://doktor-ktto-lordfilm.ru/14-sezon-1-seriya/'
sudo systemctl restart olcrtc-manager
```

Проверка вручную: `grep -v '^#' /var/lib/olcrtc/ru-direct-domains.txt | wc -l`

## Опционально (не рекомендуется)

CDN /32 снова: `OLCRTC_INCLUDE_CDN_IPS=1 setup-split-ru.sh` — может вернуть 404.

## Иностранный VPS

`--no-tor` / `--foreign` — split-скрипты **не запускаются**.

## Ссылки

- [GrimbirdUsers/ru-routing-dat](https://github.com/GrimbirdUsers/ru-routing-dat) — geosite/geoip (скрипт `fetch-geosite-ru-domains.sh`)
- [v2fly domain-list](https://github.com/v2fly/domain-list-community) — формат `domain:` / `include:` (тот же парсер)
