# Общедоступный VPS (демо / smoke-тест)

Если вы ставите стек на **общий** хост (демо для сообщества, CI, публичный sandbox) — это обычный VPS с `install.sh`, но с другими правилами безопасности, чем у приватного продакшена.

## Не размещайте на общем хосте

- Пароли и токены панели, которые вы используете в проде
- `GITHUB_TOKEN` с правами на приватные репозитории (достаточно read-only для публичных релизов или вообще без токена)
- Реальные `client_id` / подписки Olcbox пользователей
- SSH-ключи и `.env` с секретами в `/opt/Olc-cost-l` (репозиторий на VPS часто `git pull` — всё в каталоге видно с root)

Секреты только в `/etc/olcrtc-manager/` с правами root и **не** в git.

## Что можно

- Проверка `curl …/install.sh | sudo bash` и `sudo olc-update`
- Профили `ru-full`, `foreign-minimal`, toggle через `olc-feature`
- Тест мостов, zapret, WARP **без** персональных данных

## Рекомендуемая конфигурация

```bash
# Отдельный логин панели (не default admin/password из доков)
# В /etc/olcrtc-manager/panel.env — свой OLCRTC_PUBLIC_URL

# Опционально: github.env только для снятия rate limit API релизов
# packaging/olcrtc-manager/github.env.example
```

После установки смените пароль в UI и не публикуйте URL с query-токенами.

## Проверка после install

```bash
systemctl is-active olcrtc-manager tor@default
sudo olc-update --show-profile
sudo olc-feature status
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8888/admin
```

## Обновление

На любом VPS (приватном или демо):

```bash
sudo olc-update
# или
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash -s -- --update
```

См. [UPDATE.md](./UPDATE.md), [VPS-SETUP.md](./VPS-SETUP.md), [FEATURES.md](./FEATURES.md).
