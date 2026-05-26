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
| `olc-feature warp on\|off\|status`  | Cloudflare WARP (**proxy only**); взаимоисключение с Tor       |
| `olc-feature all-off`              | zapret + tor + split + warp → off (минимальный режим для тестов) |
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

## Профиль деплоя (умный update)

**Один файл** — `/etc/olcrtc-manager/deploy-profile.json`. Это не несколько отпечатков и не сумма: один JSON с флагами `components.{tor,split,zapret,bridges,warp}`.

### Два слоя состояния (не путать)

| Слой | Файл | Что означает |
|------|------|--------------|
| **Состав стека** | `deploy-profile.json` | Какие шаги гонять при `olc-update` (Tor, zapret, WARP…) |
| **Вкл/выкл сейчас** | `features.env` | Переключатели в шапке панели (сервис остановлен, конфиги на диске) |

- **± Установить/Удалить** в панели → меняет `deploy-profile.json` (после job).
- **Toggle Zp/Tor/Sp/Wt/WARP** в шапке → только `features.env`; состав стека не меняется.
- При `olc-update` шаги идут по **профилю**; после обслуживания **не включают** сервис, если в `features.env` он выключен.

### Пресеты и custom

| `profile_id` | Когда |
|--------------|-------|
| `ru-full`, `foreign-minimal`, `foreign-warp`, … | Совпадает с шаблоном в `data/deploy-profiles/` |
| `custom` | Смесь компонентов (например, zapret+split без Tor после установки через UI) |

Если набор не совпадает ни с одним шаблоном — `profile_id` становится **`custom`**, не создаётся второй файл.

### Команды

```bash
olc-profile show
olc-profile list
olc-profile set foreign-minimal
olc-profile set foreign-warp    # зарубежный VPS + WARP (без Tor)
olc-profile sync                # пересобрать профиль по установленным пакетам (ручной откат)
olc-update --show-profile
olc-update --profile ru-full
```

## Быстрое обновление

```bash
olc-update          # git pull + agent-bootstrap --update (если репо уже на VPS)
curl -fsSL .../install.sh | sudo bash   # авто: detect installed → update, fresh → full
```

## Хосты из панели (Jitsi URL)

При создании/удалении локации hostname из `room_id` (`https://jitsi.etudevs.ru/room`) добавляется в
`/var/lib/olcrtc/lists/panel-carrier-hosts.txt` и в `ru-direct-domains.txt` (для split/zapret).

```bash
olc-sync-panel-host.sh sync-config   # пересобрать из config.json
```

## Через панель

В шапке `/admin`: для каждого слоя (**Zp / Tor / Sp / Wt / WARP**) — переключатель, кнопка **логов** и **настроек** (краткая справка по слою).
Та же тройка дублируется в карточке **«Сеть и обход»** (сворачивается, состояние в `localStorage`); синхронизация через `olc-features-changed`.

- **Split** нельзя включить, пока выключен **Tor** (и в UI, и в `olc-feature split on`).
- **Tor** и **WARP** взаимоисключающие (и в UI, и в `olc-feature.sh`).
- **WARP** всегда виден в UI (даже до установки); установка — drawer **«Компоненты VPS»** (±) с job-логом и статусом после перезагрузки страницы (`GET /api/components/jobs`).
- У локации: **Стоп** (без удаления), **Restart**, **Логи**.
- **Удалить локацию** — только эта строка блокируется на ~5–15 с; остальные клиенты/кнопки активны; перезагрузка инстансов идёт в фоне.

При выключении Tor/Split панель может ответить предупреждением, а не 500 — manager перезапускается
через 2 с в фоне (иначе HTTP обрывается с `signal: terminated`).

Логи слоя: `GET /api/features/logs/{zapret|tor|split|webtunnel}` (journalctl / tail файлов).

Реализовано как:

- `GET /api/features` — возвращает `{flags, live, script}`
- `POST /api/features/{name}` — body `{"enabled": true|false}`, вызывает `olc-feature.sh <name> on|off`

Whitelist имён жёсткий (`zapret/tor/split/webtunnel/warp`), shell-injection невозможен — manager не подставляет имя в shell-строку, а передаёт его как отдельный argv. Manager уже бежит от root, дополнительный sudo не нужен.

Подробнее про WARP: [WARP-OPTIONAL.md](WARP-OPTIONAL.md).

Откатить UI (если что-то не нравится) — `olc-feature off` в CLI работает независимо.
