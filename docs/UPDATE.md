# Установка, обновление и полная переустановка

## Единый manager

Исходный код нашей панели хранится в `components/olcrtc-manager` и собирается
напрямую. Production не клонирует `local-panel-version`, не выбирает
`stable/latest` и не накладывает старый manager patch-stack. Upstream manager
используется только для покоммитного аудита; выбранные изменения вручную
адаптируются в vendored-исходник.

## Установка

```bash
# Интерактивный TUI
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh | sudo bash

# Полный RU-профиль; HTTPS self-signed по умолчанию
curl -fsSL https://raw.githubusercontent.com/krygag1234-a11y/Olc-cost-l/main/install.sh \
  | sudo bash -s -- --full --ip
```

Основные комбинации компонентов:

| Команда | Tor | Bridges | Split | Zapret | WARP |
|---|---:|---:|---:|---:|---:|
| `--full` | да | да | да | да | нет |
| `--full --no-tor` | нет | нет | нет | да | нет |
| `--full --no-bridges` | да | нет | да | да | нет |
| `--full --no-split` | да | да | нет | да | нет |
| `--full --no-zapret` | да | да | да | нет | нет |
| `--tor` | да | нет | нет | нет | нет |
| `--tor --bridges` | да | да | нет | нет | нет |
| `--tor --split` | да | нет | да | нет | нет |
| `--bridges` | не меняет | да | нет | нет | нет |
| `--split` | не меняет | нет | да | нет | нет |
| `--zapret` | нет | нет | нет | да | нет |
| `--warp` | нет | нет | нет | нет | да |

`--bridges` требует уже работающий Tor. Split без Tor и расширенная маршрутизация
на произвольную SOCKS-ноду — отдельная будущая архитектурная задача; текущий
production-сценарий Split рассчитан на установленный Tor.

Доступ и TLS:

```bash
--ip --https-self-signed   # HTTPS по IP с предупреждением браузера
--ip --https-letsencrypt   # доверенный IP-сертификат + автопродление
--ip --http                # явный HTTP
--ssh --http               # панель только на 127.0.0.1 через SSH-туннель
```

Без флагов TUI предлагает режим и компоненты. `Ctrl+O` разворачивает/сворачивает
дополнительный вывод, не создавая второй поток логов.

## Переход установщика в обновление

Повторный запуск `install.sh` обнаруживает существующую систему и предлагает
обновление. Он использует тот же vendored manager и сохранённый
`/etc/olcrtc-manager/deploy-profile.json`; отдельного старого пути сборки нет.

## `olc-update`

```bash
sudo olc-update --help
sudo olc-update                 # TUI выбора режима
sudo olc-update --update        # полная пересборка core + manager
sudo olc-update --incremental   # не трогать уже исправные компоненты
sudo olc-update --show-profile
sudo olc-update --profile ru-full --incremental
sudo olc-update --plan --profile ru-full --incremental
```

Если TLS/access не указаны, используются значения deploy-profile. Обычное
обновление не должно удалять сертификат, менять порт или включать выключенный
модуль. Перед изменениями создаётся VPS-backup; Git обновляется безопасным
fast-forward/проверяемым путём, без автоматического `reset --hard` грязного дерева.

## Продолжение прерванного запуска

```bash
sudo olc-update --resume
sudo /opt/Olc-cost-l/scripts/agent-bootstrap.sh --state
```

Состояние шагов хранится в `/var/lib/olcrtc/install-state.json`. Подробнее:
[RESUME-INSTALL.md](RESUME-INSTALL.md).

## Полная безопасная переустановка

```bash
sudo olc-reinstall --dry-run
sudo olc-reinstall
```

`olc-reinstall`:

1. создаёт полный rollback-архив VPS и логический JSON-backup;
2. сохраняет deploy-profile и точный снимок текущего vendored-исходника;
3. выполняет `olc-purge --purge-repo`;
4. восстанавливает тот же исходник и устанавливает прежний набор модулей/TLS;
5. автоматически импортирует данные и проверяет профиль, порт, HTTPS и runtime.

Rollback-архив и логический backup сохраняются. Для системы, уже установленной
vendored-pipeline, команда использует `/opt/Olc-cost-l` и не требует параметров.

Первый перевод legacy production выполняется из отдельно проверенного checkout:

```bash
sudo OLC_REINSTALL_SOURCE_DIR=/root/validated-Olc-cost-l \
  /root/validated-Olc-cost-l/scripts/olc-reinstall.sh --dry-run
sudo OLC_REINSTALL_SOURCE_DIR=/root/validated-Olc-cost-l \
  /root/validated-Olc-cost-l/scripts/olc-reinstall.sh --yes
```

В этом режиме старый `/opt/Olc-cost-l` попадает в полный rollback-архив, а после
purge устанавливаются только Git-tracked файлы и `.git` проверенного checkout.
Источник обязан быть без staged/unstaged изменений отслеживаемых файлов.

## Проверка после обновления

```bash
systemctl is-active olcrtc-manager
systemctl is-active tor@default 2>/dev/null || true
systemctl is-active zapret 2>/dev/null || true
pidof nfqws 2>/dev/null || true
sudo OLC_ALLOW_VENDORED_BUILD_STATE=1 \
  /opt/Olc-cost-l/scripts/verify-vendored-manager.sh \
  /opt/Olc-cost-l/components/olcrtc-manager
```

Панель может работать по HTTP или HTTPS и на порту из `config.json`; для CLI
экспорта/импорта используйте `olc-backup`, который определяет протокол сам.
