# Контроль доступа, подключения и рандомизация ключей

Актуально для production-сборки Olc-cost-l от 2026-07-31. Документ описывает
фактическое поведение manager и patched `olcrtc-core`, а не первоначальный план.

## Два независимых уровня

1. **Доступ к подписке** — HTTP-запрос olcbox к URL подписки. Решение принимается
   по `x-hwid`, IP и глобальным либо per-client спискам.
2. **Доступ к подключению** — `CLIENT_HELLO` внутри туннеля. Решение принимает
   `AuthHook` в core по device id, выбранному инстансу и классу криптоключа.

Списки этих уровней независимы:

- подписка: `devices`, `ban`, `allowed_ips`, `ban_ips`;
- подключение: `conn_devices`, `conn_ban`;
- per-client: `allow`, `ban`, `allow_ips`, `ban_ips`, `conn_allow`, `conn_ban`.

Бан действует даже в режиме «выключено». Allowlist начинает ограничивать доступ
только в соответствующем enforce-режиме.

## Идентификатор устройства

В Identity-режиме olcbox отправляет `x-hwid: install-<32 hex>`. Это стабильный
идентификатор конкретной установки приложения. Compatibility-запрос может прийти
без `x-hwid`; для него отдельно существует `ban_no_hwid`.

На HTTP-уровне manager также видит User-Agent и адрес запроса. На WebRTC-уровне
core получает device id из handshake; IP HTTP-запроса там недоступен.

## Доступ к подписке

Глобальный контроль включается полем `enabled`. Пока он включён, используются
только глобальные списки. Когда он выключен, применяются настройки конкретного
клиента из `clients[client_id]`.

Режимы подписки:

- `monitor` / «выключено» — пропускать всех, кроме ban-листа, и вести журнал;
- `enforce` — пропускать только активные записи allowlist; ban имеет приоритет.

Per-client `off` и `monitor` имеют одинаковое пропускающее поведение. Запись
клиента сохраняется, чтобы параллельное изменение одного поля не стирало другие.
API использует частичные обновления: отсутствующее поле не меняется, пустой массив
явно очищает соответствующий список.

Неизвестное устройство в `enforce` получает 404. Проверка выполняется до выдачи
профиля и до резолва рандомизированного client id. Разрешённый HWID может получить
подписку по оригинальному client id; для неизвестного оригинальный путь скрыт.

## Доступ к подключению

Core читает `/var/lib/olcrtc/access-control.json` на handshake. Контекст инстанса
передаётся manager через `OLCRTC_CLIENT_ID` и `OLCRTC_ROOM_ID`.

Режимы `conn_mode`:

| Режим | Оригинальный ключ | Рандомизированный ключ | Allowlist | Ban |
|---|---|---|---|---|
| `off` | разрешён | разрешён | не ограничивает | всегда блокирует |
| `keyrand` | только разрешённому устройству | разрешён неизвестному и разрешённому | определяет доступ по оригинальному ключу | всегда блокирует |
| `enforce` | только allowlist | только allowlist | обязателен для обоих классов ключа | всегда блокирует |

Точная принятая матрица `keyrand`:

- разрешённое устройство + оригинальный ключ → allow;
- неизвестное устройство + оригинальный ключ → reject;
- неизвестное устройство + рандомизированный ключ → allow;
- забаненное устройство с любым ключом → reject.

При повторной проверке уже живой сессии класс ключа не используется: watcher не
кикает неизвестного только потому, что после handshake уже нельзя восстановить
класс ключа. Ban и изменение allowlist всё равно применяются.

### Глобальный и выборочный scope

Если глобальный `enabled=true`, параметры подключения берутся из глобальных
`conn_*`; per-client настройки временно не участвуют. Если глобальный контроль
выключен, используется `clients[client_id]`.

- `conn_scope=all` — режим действует на все инстансы области;
- `conn_scope=selective` — `conn_instances` является whitelist комнат.

В активном `keyrand`/`enforce` невыбранный room отклоняет подключения, а не
остаётся открытым. Пустой allowlist в `enforce` блокирует всех. Fail-open
допускается только при ошибке чтения или разбора JSON и сопровождается WARN-логом.

## Рандомизация криптоключей

Видимые настройки рандомизации типа/scope синхронизируются с
`/var/lib/olcrtc/key-randomization.json`:

- scope `client_id` отключает крипторандомизацию;
- scope `crypto` или `both` включает её с выбранным типом;
- после изменения manager перезапускает только затронутые клиенты, чтобы новые
  env-переменные дошли до core.

Оригинальный ключ `Endpoint.Key` при этом не изменяется. Автосмена оригинального
ключа — отдельная функция key rotation.

### Тип 1

Статичный производный ключ:

`HMAC-SHA256(randomization_secret, original_key_bytes)`.

Manager передаёт его в `OLCRTC_ALT_KEYS`. Core на первом зашифрованном фрейме
определяет, какой cipher подошёл, фиксирует его и тем же cipher шифрует ответы.

### Тип 2

Динамический ключ меняется каждую секунду. Manager передаёт
`OLCRTC_ALT_KEY_MODE=2` и `OLCRTC_ALT_KEY_SECRET`; core выводит ключ для текущей
и предыдущей секунды. Окно предыдущей секунды компенсирует границу секунд и
не превращает ключ в долгоживущий.

`GET /api/instances/info?client_id=...&room_id=...` показывает оригинальный ключ,
текущий производный ключ, тип и `dynamic`. Для типа 1 fingerprint постоянен, для
типа 2 меняется между секундами.

## Живые сессии и журналы

Handshake-hook отклоняет новые подключения. Дополнительно ban-watcher каждые две
секунды проверяет живые peer-сессии и точечно отключает запрещённый device. В
legacy singleton-пути выполняется переустановка сессии. Остальные устройства
инстанса при per-peer kick не затрагиваются.

Manager ведёт два разных журнала:

- `/var/lib/olcrtc/access-attempts.json` — запросы подписки, сгруппированные по
  `(hwid, client_id)` со счётчиком;
- `/var/lib/olcrtc/access-connections.json` — подключения/отказы core по
  устройству, клиенту и инстансу.

Формат connection-журнала v2 содержит `cleared_at`, `cleared_clients` и
`records`. Водяные знаки не дают старым строкам кольцевого log-buffer воскресить
очищенные записи. Строки `allowed=false` считаются отказами, а не успешными
подключениями.

## Удаление клиента и локации

Удаление клиента очищает:

- `config.json` и встроенную client randomization;
- `access-control.json`, subscription attempts и connection records;
- per-client key rotation/rounds;
- per-client key randomization;
- запущенные процессы клиента.

`cleared_clients[client_id]` после удаления остаётся намеренно как временная
водяная метка, а не как осиротевший клиент. Удаление отдельной локации убирает её
room id из selective scope и её connection history; клиентские настройки
рандомизации и rotation сохраняются.

## Основные API (adminAuth)

- `GET|PUT /api/access/settings` — глобальные настройки, частичный PUT;
- `GET|POST /api/access/client` — per-client настройки, частичный POST;
- `GET /api/access/attempts`, `POST /api/access/attempts/clear`;
- `POST /api/access/allow`, `/api/access/remove`, `/api/access/device`;
- `GET /api/access/connections`; `?clear=1` очищает всё, а
  `?clear=1&client_id=ID` — только выбранного клиента;
- `GET|PATCH /api/settings/key-randomization`;
- `POST|PUT|PATCH /api/clients/:id/key-randomization`;
- `GET /api/instances/info?client_id=ID&room_id=ROOM`.

## Хранение и бэкап

- `/var/lib/olcrtc/access-control.json` — настройки и списки;
- `/var/lib/olcrtc/key-randomization.json` — scope/type/secret крипторандомизации;
- `/var/lib/olcrtc/key-rotation.json` — отдельная смена оригинальных ключей;
- `/var/lib/olcrtc/access-attempts.json` и `access-connections.json` — журналы.

В пользовательский backup входят access-control, key-randomization и
key-rotation. Журналы попыток/подключений намеренно не переносятся.

## Проверки 2026-07-31

В Linux-аудите проходят:

- `TestOlcAccessKeyrandMatrix` — `off/keyrand/enforce`, ban и selective room;
- все muxconn-тесты выбора и latch cipher;
- тесты type-2 current/previous-second provider;
- manager build и live env/info-проверка типов 1/2;
- live delete test клиента со включёнными access, rotation и type 2.

Известный `wb/kr4 exited` относится к высыханию wbstream-комнаты без бота или
перегенерации токена и не является дефектом access/delete/crypto.

## Правило синхронизации для разработчиков

При изменении структуры access JSON нужно одновременно обновлять:

1. manager-модель и API в `patch-olcrtc-manager-access-control-api.sh`;
2. зеркальную core-модель и решение в `patch-olcrtc-core-access-hook.sh` и
   `patch-olcrtc-core-key-randomization.sh`;
3. UI глобального и per-client контроля;
4. backup manifest/migration и cleanup удаления;
5. матричные тесты handshake/recheck.
