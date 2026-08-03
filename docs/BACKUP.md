# Бекап и восстановление данных панели (экспорт / импорт)

Панель Olc-cost-l умеет сохранить **все ваши данные** в один JSON-файл и
восстановить их — после переустановки, на новом VPS или после сбоя.

> ⚠️ **Приватность.** Файл бэкапа и вся аналитическая/конфигурационная информация
> хранятся **исключительно на ваших устройствах** — там, где находится панель, и
> там, куда вы скачиваете файл. Панель/сервер **никуда** эти данные не отправляет.
> В бэкапе есть чувствительное (пароль панели, ключи подписки) — храните файл в
> надёжном месте.

## Где в UI

Модалка **Настройки** → секция **«Бекап данных»**:
- **Экспортировать (скачать JSON)** — скачивает `olc-backup-<дата>.json` со всеми данными.
- **Импортировать (выбрать JSON)** — загружает такой файл и восстанавливает данные.

После успешного импорта UI показывает реальную кнопку **«Перезапустить панель»**,
ждёт возвращения сервиса и затем обновляет страницу.

### Защита от сервера-двойника

Экспорт содержит `source_host_id` текущего VPS. Если бэкап с активными `room+key`
импортируется на другой VPS (или это старый бэкап без `source_host_id`), backend
до любой записи возвращает HTTP 409. UI показывает отдельное предупреждение:
второй работающий сервер с теми же room+key неотличим для клиента. Продолжение
возможно только после явного подтверждения, когда исходный сервер остановлен
или перенос выполняется осознанно.

### Отсутствующие модули при импорте

Начиная со schema `3`, export сохраняет снимок `components` с признаками `installed` и `enabled`.
Если в backup были установлены Tor, Bridges, Split, Zapret или WARP, а на целевом VPS их нет,
backend до любой записи возвращает HTTP 409 и полный список недостающих модулей.

UI предлагает три действия:

- отменить импорт без изменений на диске;
- пропустить только настройки и состояния отсутствующих модулей;
- восстановить данные и последовательно доустановить модули через штатные component jobs.


## Что попадает в бэкап

| Ключ в бэкапе | Источник на диске | Что это |
|---|---|---|
| `config` | `/etc/olcrtc-manager/config.json` | серверы, локации, клиенты, инстансы, подписка, глобальные настройки |
| `panel_env` | `/etc/olcrtc-manager/panel.env` | доступ к панели, логин/пароль, режим (IP/SSH), split-переменные |
| `features_env` | `/etc/olcrtc-manager/features.env` | вкл/выкл компонентов (Tor/Split/Zapret/WARP) |
| `deploy_profile` | `/etc/olcrtc-manager/deploy-profile.json` | профиль установки |
| `notification_settings` | `/etc/olcrtc-manager/notification-settings.json` | настройки уведомлений |
| `instance_defaults` | `/var/lib/olcrtc/instance-defaults.json` | значения по умолчанию для инстансов |
| `access_control`, `access_attempts`, `access_connections` | `/var/lib/olcrtc/access-*.json` | правила доступа и журнал попыток/подключений |
| `key_rotation`, `key_randomization` | `/var/lib/olcrtc/key-*.json` | автосмена и криптографическая рандомизация |
| `bridge_sources`, `bridge_profiles`, `tor_user_bridges` | `/var/lib/olcrtc/...` | источники, профили и пользовательские мосты |
| `torrc`, `tor_bridges`, `tor_exit_env`, `tor_exit_exclude_env` | `/etc/tor/*`, `/etc/olcrtc-manager/tor-exit*.env` | пользовательские настройки Tor и мостов |
| `split_panel_hosts`, `split_panel_cidrs`, `split_discovered` | `/var/lib/olcrtc/lists/panel-carrier-*` | ручные/автоматические правила Split и их группы |
| `custom_direct_domains`, `force_tor_domains`, `ru_blocked_tor_domains`, `ru_domains_extra` | `/var/lib/olcrtc/...` | пользовательские списки маршрутизации |
| `zapret_exclude_domains`, `zapret_force_domains`, `zapret_strategy` | `/var/lib/olcrtc/zapret-custom/*`, `/etc/olcrtc-manager/zapret.strategy` | пользовательские настройки Zapret |
| `zapret_sync_cron`, `bridge_pool_cron` | `/etc/cron.d/olcrtc-*` | включённые пользователем фоновые обновления |
| `install_profile`, `github_env` | `/var/lib/olcrtc/install-profile.json`, `/etc/olcrtc-manager/github.env` | профиль установки и настройки обновления из GitHub |

## Почему бэкап устойчив к смене версий панели

Проблема: вы сохранили бэкап на старой версии панели, а восстанавливаете на
новой, где что-то переделано. Решение — **два принципа**:

1. **Хранится СЫРОЙ JSON.** Экспорт не пропускает данные через Go-структуры, а
   сохраняет `config.json` как есть (generic JSON). Поэтому никакие поля не
   «срезаются», даже если текущая версия про них не знает.
2. **Импорт делает поключевой deep-merge.** Значения из бэкапа накладываются
   поверх текущих дефолтов:
   - вложенные объекты сливаются по ключам;
   - массивы и скаляры (список клиентов, локаций, инстансов) заменяются целиком;
   - **новые** поля, появившиеся в новой версии, сохраняют свои дефолты (их нет в
     старом бэкапе — они не затираются);
   - **устаревшие** поля из старого бэкапа просто игнорируются новой панелью.

Стабильные идентификаторы, «привязанные» к каждой настройке — это **сами ключи
JSON** и имена файлов из таблицы выше. Для явных переименований ключей между
версиями есть хук миграции `migrateBackup(schemaVersion, env)` на бэкенде.

Каждый бэкап помечен `schema_version`. Если файл новее, чем понимает панель,
импорт откажется (просит обновить панель).

## ⛔ ПРАВИЛО ДЛЯ РАЗРАБОТЧИКОВ (ОБЯЗАТЕЛЬНО)

**Если вы добавляете/меняете/переименовываете любую настройку, состояние,
запоминаемый выбор пользователя или файл, который должен переживать
переустановку/перенос — вы ОБЯЗАНЫ адаптировать бэкап:**

1. Убедитесь, что новые данные лежат **в `config.json`** ИЛИ **в одном из файлов**
   из `backupExtraFiles()` в `components/olcrtc-manager/cmd/olcrtc-manager/main.go`.
   Если это новый файл настроек — **добавьте его** в `backupExtraFiles()`.
2. При **переименовании/переезде** ключа добавьте преобразование в
   `migrateBackup()` (там же), сверяясь с `schema_version`, и поднимите
   `olcBackupSchemaVersion` при несовместимых изменениях формата.
3. В vendored UI (`components/olcrtc-manager/src/main.tsx`) новые настройки должны
   в итоге сохраняться в один из перечисленных файлов — иначе они не попадут в бэкап.
4. Обновите таблицу «Что попадает в бэкап» в этом файле.

5. Если меняется структура JSON-конверта, повысить `schema_version` и добавить последовательный шаг в
   `migrateBackup()`. Все ранее выпущенные шаги миграции сохраняются: старый backup должен декодироваться
   до текущей схемы, а импорт не должен ничего записывать до успешного завершения миграции.
6. Backup с более новой схемой отклоняется до записи. После готовности обновления из UI панель должна
   предложить обновление с логами и автоматически продолжить импорт уже загруженного файла после
   возвращения backend, без повторного выбора файла.

Соответствующие предупреждающие комментарии продублированы прямо в коде:
- бэкенд: `components/olcrtc-manager/cmd/olcrtc-manager/main.go` (блок `Backup / Restore`);
- фронтенд: `components/olcrtc-manager/src/main.tsx` (компонент `BackupSection`).

## API (для CLI/автоматизации)

- `GET  /api/backup/export` (admin-auth) → JSON-конверт (заголовок
  `Content-Disposition: attachment`).
- `POST /api/backup/import` (admin-auth) — тело: JSON-конверт; ответ:
  `{"status":"ok","restored":[...],"note":"..."}`.
- `POST /api/backup/import?confirm_foreign_host=1` — явное подтверждение импорта
  активных room+key с другого/неизвестного хоста после ответа 409.
- `POST /api/backup/restart` — отложенно перезапускает `olcrtc-manager`, успев
  вернуть браузеру `{"status":"ok","restarting":true}`.

Пример (с боевого/локального хоста):

```bash
# экспорт
curl -fsS -u admin:ПАРОЛЬ http://127.0.0.1:8888/api/backup/export -o olc-backup.json
# импорт
curl -fsS -u admin:ПАРОЛЬ -X POST http://127.0.0.1:8888/api/backup/import \
  -H 'Content-Type: application/json' --data-binary @olc-backup.json
```

## Полный manifest после аудита 2026-07-31

Экспорт панели сохраняет `config` и следующие дополнительные элементы:

- `panel_env`, `features_env`, `deploy_profile`;
- `notification_settings`, `instance_defaults`, `access_control`;
- `key_rotation`, `key_randomization`;
- `bridge_sources`, `force_tor_domains`, `ru_blocked_tor_domains`;
- `custom_direct_domains`, `ru_domains_extra`, `split_discovered`.
- `split_panel_hosts`, `split_panel_cidrs`;
- `zapret_exclude_domains`, `zapret_force_domains`, `zapret_strategy`, `zapret_sync_cron`;
- `tor_exit_env`, `tor_exit_exclude_env`, `torrc`, `tor_bridges`, `tor_user_bridges`;
- `bridge_profiles`, `bridge_pool_cron`, `install_profile`, `github_env`;
- `access_attempts`, `access_connections`.

JSON-файлы сохраняются как `kind: "json"`, env-файлы — как `kind: "env"`,
обычные списки доменов — целиком как `kind: "text"`. Перед заменой любого
дополнительного файла импорт создаёт рядом копию `.bak-import-<timestamp>` и
записывает новое содержимое атомарно через временный файл.

## Формат конверта (schema_version 3)

```json
{
  "olc_backup": true,
  "schema_version": 3,
  "app": "olcrtc-manager",
  "source_host_id": "machine-id-of-source-vps",
  "created_at": "2026-07-16T21:40:00Z",
  "note": "Эти данные принадлежат только вам и хранятся локально…",
  "manifest": ["config", "panel_env", "features_env", "..."],
  "components": { "tor": { "installed": true, "enabled": true }, "warp": { "installed": false, "enabled": false } },
  "config": { "...": "сырой config.json" },
  "extras": {
    "panel_env":    { "kind": "env",  "values": { "OLCRTC_MANAGER_USER": "admin", "...": "..." } },
    "deploy_profile": { "kind": "json", "value": { "...": "..." } }
  }
}
```
