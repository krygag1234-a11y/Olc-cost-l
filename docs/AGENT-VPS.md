# [DEV] Карта runtime VPS для агентов

**Актуально для vendored-pipeline с 2026-08-10.** Конкретные IP, commit и
состояние сервисов всегда перепроверяются live.

## Пути

| Путь | Назначение |
|---|---|
| `/opt/Olc-cost-l` | checkout проекта и vendored manager |
| `/usr/local/bin/olcrtc-manager` | собранный manager |
| `/usr/local/bin/olcrtc` | собранный OlcRTC core |
| `/etc/olcrtc-manager/config.json` | клиенты/локации/порт |
| `/etc/olcrtc-manager/panel.env` | доступ, TLS, публичный URL и настройки core |
| `/etc/olcrtc-manager/features.env` | runtime-флаги модулей |
| `/etc/olcrtc-manager/deploy-profile.json` | профиль install/update/reinstall |
| `/var/lib/olcrtc` | пользовательское состояние и install state |
| `/var/backups/olc-vps` | полные rollback-архивы |
| `/var/backups/olc-reinstall` | логические backup и рабочие данные reinstall |

## Команды

```bash
sudo olc-update --help
sudo olc-update --incremental
sudo olc-update --update
sudo olc-backup export /root/olc-backup.json
sudo olc-reinstall --dry-run
sudo olc-purge --dry-run
```

## Проверка runtime

```bash
systemctl is-active olcrtc-manager
systemctl is-active tor@default 2>/dev/null || true
systemctl is-active zapret 2>/dev/null || true
pidof nfqws 2>/dev/null || true
jq . /etc/olcrtc-manager/deploy-profile.json
sudo /opt/Olc-cost-l/scripts/verify-vendored-manager.sh
```

Протокол и порт нельзя угадывать: порт читается из `config.json`, TLS — из
`panel.env`. `olc-backup` определяет HTTP/HTTPS автоматически.

## Маршрут управления VPS

Windows — только управляющее устройство. Операции на Linux выполняются через
exec API; RU достигается из API-VPS командой `ssh ru`. Прямой SSH используется
как break-glass. API-VPS имеет динамический IP, поэтому основной адрес — DDNS
домен из handoff, а не сохранённый IP.

## Изменения production

Сначала read-only аудит и backup, затем тест на API-VPS. Перевод production RU
на vendored-pipeline — отдельная миграция; обычный `olc-update` не используется
для первого перехода со старой структуры.
