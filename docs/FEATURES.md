# Feature toggles

`olc-feature` — переключение слоёв стека на живом VPS без переустановки. Удобно для:

- быстрых тестов (отключить `zapret`/`Tor`/`split`, проверить чистый olcrtc → enable обратно);
- иностранного VPS (мы выключаем `tor`/`split`/`zapret` после установки одной командой);
- багрепортов («работает ли без zapret?» — `olc-feature zapret off` → проверить → `… on`).

Управляющий файл: `/etc/olcrtc-manager/features.env` (читается `agent-bootstrap.sh` и cron).

## Команды

| Команда                            | Что делает                                                     |
| ---------------------------------- | -------------------------------------------------------------- |
| `olc-feature status`               | Текущие toggle + live-состояние сервисов                       |
| `olc-feature zapret on\|off\|reload` | Старт/стоп `zapret` (config + списки сохраняются)              |
| `olc-feature tor on\|off`           | Старт/стоп `tor@default`, убирает `OLCRTC_EXIT_PROXY` у панели |
| `olc-feature split on\|off`         | Включает/выключает `*.ru`/CDN direct-списки для olcrtc         |
| `olc-feature webtunnel on\|off`     | Скачивает binary из mirror-cry / удаляет                       |
| `olc-feature all-off`              | zapret + tor + split → off (минимальный режим для тестов)      |
| `olc-feature all-on`               | Восстановить все слои                                          |

Симлинк, чтобы не писать полный путь:

```bash
sudo ln -sf /opt/Olc-cost-l/scripts/olc-feature.sh /usr/local/bin/olc-feature
```

## Безопасность отключения

- ничего не удаляется на диске (пакеты, конфиги, бриджи, списки);
- модифицируемые файлы бэкапятся в `/var/lib/olcrtc/feature-backups/*.bak.<ts>`;
- `tor off` лишь останавливает службу и снимает зависимость с панели — bridges.conf на месте;
- `zapret off` убивает `nfqws` и снимает `iptables` правила процесса; правила инициализации zapret вернутся при `on`;
- `webtunnel off` удаляет binary и строки `Bridge webtunnel`/`ClientTransportPlugin webtunnel` из `bridges.conf`, обфы остаются;
- `split off` уносит файлы `/var/lib/olcrtc/lists/*.txt` в `disabled/` и перезапускает панель.

Откат — обратной командой (`on`).

## Через панель

В админке (`/admin`) появилась карточка **Network features** под заголовком: показывает текущие toggle + live-состояние сервисов, кнопки `Enable/Disable` для каждого. Реализовано как:

- `GET /api/features` — возвращает `{flags, live, script}`
- `POST /api/features/{name}` — body `{"enabled": true|false}`, вызывает `olc-feature.sh <name> on|off`

Whitelist имён жёсткий (`zapret/tor/split/webtunnel`), shell-injection невозможен — manager не подставляет имя в shell-строку, а передаёт его как отдельный argv. Manager уже бежит от root, дополнительный sudo не нужен.

Откатить UI (если что-то не нравится) — `olc-feature off` в CLI работает независимо.
