# ЭПИК A — Крипто-рандомизация ключей: ЧЕРНОВИК кода частей 2–6

> **СТАТУС:** Часть 1 (multi-key в muxconn) — СДЕЛАНА и задеплоена инертно
> (`patch-olcrtc-core-key-randomization.sh`, коммит `2c25753`). Части 2–6 ниже —
> ЧЕРНОВИК кода (НЕ задеплоено, НЕ зарегистрировано в `apply-olcrtc-patches.sh`).
> Это заготовки, сохранённые в репо (у нового агента нет доступа к песочнице).
>
> **Baseline:** olcrtc-core ПИН `6fa08e7f907775aef4a994c6a1f06d29a5f23430` (Урок 69).
> **Семантика:** Вариант A (неразрешённому оригинальный ключ не работает; бан
> абсолютен; тип2 — реальный посекундный, не имитация). Всё OFF по умолчанию.
>
> Валидация после сборки частей: свежий клон → `git fetch origin <ПОЛНЫЙ SHA> --depth 1
> && git reset --hard <ПОЛНЫЙ SHA>` → access-hook → key-randomization → части 2–4 →
> `go build ./internal/server/ ./internal/app/session/ ./internal/muxconn/ ./internal/handshake/`
> + `go test ./internal/muxconn/`.

---

## ЧАСТЬ 2 — handshake.go: проброс keyClass в hook (без ломки AuthFunc)

`internal/handshake/handshake.go`. AuthFunc НЕ меняем (обратная совместимость).
Меняем сигнатуру `Server` (+keyClass) и инжектим reserved-claim перед вызовом auth.

```go
// БЫЛО:  func Server(rw io.ReadWriter, auth AuthFunc) (Hello, string, error) {
// СТАЛО:
func Server(rw io.ReadWriter, auth AuthFunc, keyClass int) (Hello, string, error) {
    ... (без изменений до вызова auth) ...

    // Olc-cost-l key-randomization: пробрасываем класс ключа (0 ориг / 1 ранд /
    // -1 single-cipher), которым muxconn расшифровал этот handshake, в hook
    // через reserved-claim. Клиент это поле НЕ контролирует (сервер перезаписывает).
    if h.Claims == nil {
        h.Claims = map[string]any{}
    }
    h.Claims["_olc_key_class"] = keyClass

    sessionID, err := auth(h.DeviceID, h.Claims)   // строка ~178, без изменений
    ...
}
```

`internal/handshake/handshake_test.go`: во всех вызовах `Server(sConn, func...)` →
`Server(sConn, func..., 0)` (build тесты не гоняет, но для чистоты).

---

## ЧАСТЬ 2 — server.go: alt-ciphers + SetAltCiphers + keyClass в handshake

`internal/server/server.go` (пин 6fa08e7).

**(a) Config struct** (~137) — добавить поле:
```go
    // AltKeysHex: доп. hex-ключи (32 байта) для приёма от НЕразрешённых устройств
    // (key-randomization тип1: 1 статичный; тип2: [rand(t), rand(t-1)] — обновляется
    // снаружи). Пусто → single-cipher (upstream). Olc-cost-l.
    AltKeysHex []string
```

**(b) Server struct** — добавить поле:
```go
    altCiphers []*crypto.Cipher
```

**(c) Run** (~175, после setupCipher) — построить altCiphers:
```go
    var altCiphers []*crypto.Cipher
    for _, hx := range cfg.AltKeysHex {
        ac, aerr := setupCipher(hx)   // тот же runtime.SetupCipher: hex(64)→32b
        if aerr != nil {
            logger.Warnf("olc key-rand: bad alt key (skipped): %v", aerr)
            continue
        }
        altCiphers = append(altCiphers, ac)
    }
```
И в `s := &Server{ ... }` добавить `altCiphers: altCiphers,`.

**(d) SetAltCiphers на КАЖДОМ conn** (7 мест; NewControl/NewPeerControl могут
вернуть nil → guard). После каждого создания conn:
```go
    conn := muxconn.New(s.ln, s.cipher)
    conn.SetAltCiphers(s.altCiphers...)          // + эта строка (пусто altCiphers = no-op)
```
```go
    controlConn := muxconn.NewControl(s.ln, s.cipher)
    if controlConn != nil { controlConn.SetAltCiphers(s.altCiphers...) }
```
Сайты (пин 6fa08e7): 354 (conn), 364 (controlConn), 401 (controlConn), 455
(controlConn NewPeerControl), 542 (conn), 551 (r.controlConn), 803 (conn NewPeer).

**(e) keyClass в handshake.** `acceptHandshake(ctx, sess)` не знает conn → добавить
параметр conn:
```go
// БЫЛО:  func (s *Server) acceptHandshake(ctx context.Context, sess *smux.Session) bool {
// СТАЛО:
func (s *Server) acceptHandshake(ctx context.Context, sess *smux.Session, conn *muxconn.Conn) bool {
    ...
    kc := -1
    if conn != nil { kc = conn.KeyClass() }
    hello, sid, err := handshake.Server(stream, s.authHook, kc)   // ~987
    ...
}
```
Вызовы acceptHandshake (пин): 375 `go s.acceptHandshake(s.baseCtx, controlSess, controlConn)`;
415 `..., controlConn)`; 525 `..., r.controlConn)`; 913 `s.acceptHandshake(ctx, sess, s.conn)`
(проверить, что здесь conn = s.conn — data-путь без control-plane); 1150
`s.acceptHandshake(s.baseCtx, ps.session, ps.conn)`.
acceptPeerHandshake (~1018): `hello, sid, err := handshake.Server(stream, s.authHook, ps.controlConn.KeyClass())`
(или ps.conn — тот, на котором идёт ps.controlSess; проверить по коду).

**ВАЖНО:** conn для handshake = тот, чью сессию (`sess`) accept'им. Для control-plane
транспорта это controlConn/r.controlConn; для data-пути — s.conn; для peer —
ps.controlConn (или ps.conn). Свериться с installSession/reinstall/peer по коду.

---

## ЧАСТЬ 3 — session.go: env alt-ключей

`internal/app/session/session.go`, где собирается `server.Config` (~648-685).
Добавить чтение env инстанса (менеджер передаёт при вкл. key-rand):
```go
// перед server.Run(ctx, server.Config{...})
var olcAltKeys []string
if v := strings.TrimSpace(os.Getenv("OLCRTC_ALT_KEYS")); v != "" {
    for _, k := range strings.Split(v, ",") {
        if k = strings.TrimSpace(k); k != "" { olcAltKeys = append(olcAltKeys, k) }
    }
}
```
И в server.Config добавить `AltKeysHex: olcAltKeys,` (в ОБА места где Config — ~648 и ~685).

---

## ЧАСТЬ 4 — hook: правило Варианта A (олc_access_hook.go)

В `patch-olcrtc-core-access-hook.sh` (генерирует olc_access_hook.go). Хук сейчас:
`func olcAccessConnectionAuthHook(deviceID string, _ map[string]any) (string, error)`.
Меняем на чтение claims + ИЗОЛИРОВАННУЮ функцию решения key-rand:

```go
func olcAccessConnectionAuthHook(deviceID string, claims map[string]any) (string, error) {
    dev := strings.TrimSpace(deviceID)
    keyClass := -1
    if claims != nil {
        if v, ok := claims["_olc_key_class"].(int); ok { keyClass = v }
        // json может дать float64 — подстраховка:
        if f, ok := claims["_olc_key_class"].(float64); ok { keyClass = int(f) }
    }
    // Обычное решение доступа (бан абсолютен, enforce-вайтлист) — как сейчас.
    base := olcAccessConnDecide(dev)   // существующая функция
    // ДОП. правило key-randomization (Вариант A). Активно только когда key-rand
    // включён для инстанса (keyClass >= 0 = muxconn имел alt-ключи). keyClass==-1
    // → single-cipher → поведение НЕ меняется.
    if !olcKeyRandDecide(dev, keyClass, base) {
        room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
        logger.Infof("olc-access: conn attempt device=%s allowed=false room=%s (key-rand)", dev, room)
        return "", errors.New("device not allowed to connect")
    }
    if base {
        return uuid.NewString(), nil
    }
    room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
    logger.Infof("olc-access: conn attempt device=%s allowed=false room=%s", dev, room)
    return "", errors.New("device not allowed to connect")
}

// olcKeyRandDecide — Вариант A. Возвращает true=пропускать (по правилу key-rand),
// false=reject. ⚠️ ЛЕГКО ПЕРЕКЛЮЧИТЬ НА ВАРИАНТ B: сделать `return true` (keyClass
// не влияет — доступ решает только base/контроль доступа).
//   keyClass == -1 : key-rand выкл (single-cipher) → не вмешиваемся (true).
//   keyClass == 1  : рандомизированный ключ → пропускаем (обладание ранд-ключом =
//                    прошёл барьер; финальный доступ решит base/контроль доступа).
//   keyClass == 0  : оригинальный ключ → пускать ТОЛЬКО если устройство разрешено
//                    (в conn_allow/conn_devices); иначе reject (ждём рандомизированный).
func olcKeyRandDecide(dev string, keyClass int, base bool) bool {
    if keyClass < 0 {
        return true // key-rand выкл
    }
    if keyClass == 1 {
        return true // рандомизированный ключ — барьер пройден
    }
    // keyClass == 0 (оригинальный): разрешён только для «известных» устройств.
    // «Известное» = в списке разрешённых подключения (olcAccessConnDecide это уже
    // учитывает при enforce; но key-rand требует явной принадлежности к allow даже
    // без enforce). Используем отдельную проверку членства в allow-списке.
    return olcDevInConnAllow(dev)   // РЕАЛИЗОВАТЬ: чтение conn_allow/conn_devices из
                                    // access-control.json для текущего client_id/глоб.
}
```
`olcDevInConnAllow(dev)` — новый хелпер: читает access-control.json (как
olcAccessConnDecide), возвращает true если dev в conn_devices (глоб., при enabled)
или в clients[cid].conn_allow (при выкл. глоб.). Учесть регистр (EqualFold) и Enabled.

**ВНИМАНИЕ по Варианту A:** «известное устройство» для orig-ключа = членство в
allow-списке. Если у юзера контроль доступа ВЫКЛ и allow пуст — при key-rand ВКЛ
НИКТО не пройдёт по orig-ключу (все неразрешённые). Это и есть барьер. Если это
не то — Вариант B (olcKeyRandDecide → return true) убирает влияние keyClass.

---

## ЧАСТЬ 5 — manager: вывод alt-ключа + передача + UI + конфиг

**(a) Вывод alt-ключа.** origKey в config = `Endpoint.Key` (64-hex). ДЕКОДИРОВАТЬ
в 32 байта, затем:
- тип1 (статичный): `alt = HMAC_SHA256(RandomizationSecret, origKeyBytes)[:32]` → hex(64).
- тип2 (посекундный): `alt(t) = HMAC_SHA256(RandomizationSecret, origKeyBytes || bigEndian(unixSec))[:32]`.
Секрет `RandomizationSecret` уже в config.json; хелпер hmac есть (см. `rotatingHashAt`
в main.go, использует hmac.New(sha256.New, []byte(secret))). Пример:
```go
func olcAltKeyHex(secret string, origKeyHex string, unixSec int64, type2 bool) (string, error) {
    ob, err := hex.DecodeString(origKeyHex)
    if err != nil || len(ob) != 32 { return "", fmt.Errorf("bad orig key") }
    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write(ob)
    if type2 {
        var b [8]byte; binary.BigEndian.PutUint64(b[:], uint64(unixSec)); mac.Write(b[:])
    }
    sum := mac.Sum(nil) // 32 байта
    return hex.EncodeToString(sum[:32]), nil
}
```

**(b) Передача в инстанс.** В startInstance (cmd.Env, main.go ~1786/1816) добавить,
когда key-rand ВКЛ для клиента:
- тип1: `cmd.Env = append(cmd.Env, "OLCRTC_ALT_KEYS="+altHex)`.
- тип2: инстансу нужно ПОСЕКУНДНОЕ обновление. Варианты: (i) core сам деривит
  (передать секрет+origkey+flag type2 через env, core-горутина раз в сек пересобирает
  altCiphers=[rand(t),rand(t-1)] и зовёт SetAltCiphers на живых conn под локом —
  требует хранить список conn в Server); (ii) менеджер раз в сек шлёт новые env —
  НЕЛЬЗЯ (env не меняется у живого процесса). → тип2 ТРЕБУЕТ core-деривации.
  Для тип2 передать `OLCRTC_KEYRAND_SECRET`, `OLCRTC_KEYRAND_ORIGKEY`, `OLCRTC_KEYRAND_TYPE=2`.

**(c) Конфиг состояния** — отдельный файл `/var/lib/olcrtc/key-randomization.json`
(как key-rotation.json): `{global:{enabled,type}, clients:{id:{enabled,type}}}`.
API: GET/PATCH `/api/settings/key-randomization` + POST `/api/clients/:id/key-randomization`.

**(d) UI** — ОТДЕЛЬНАЯ секция «Рандомизация ключей (тип1/тип2)» рядом с рандомизацией
client_id и ♻️ автосменой (цветные кнопки, глоб./выборочно). Предупреждение: тип2
без контроля доступа бесполезен.

---

## ЧАСТЬ 6 — тип2 (посекундный) в core

Статичный `AltKeysHex` не годится (ключ меняется каждую секунду). Нужно:
- core деривит `rand(t)`, `rand(t-1)` из секрета+origkey (env OLCRTC_KEYRAND_*).
- Server держит окно и раз в секунду пересобирает altCiphers=[cipher(rand(t)),
  cipher(rand(t-1))]; зовёт conn.SetAltCiphers на ЖИВЫХ conn под локом. → Server
  должен вести список активных conn (slice под mu), или muxconn получает
  cipher-provider callback `func() []*crypto.Cipher` вместо статичного среза
  (тогда decryptFrame зовёт провайдер — но это hot-path, кешировать на секунду).
- Живой туннель держит залатченный ключ до reconnect (ре-кей на лету невозможен) —
  «каждую секунду» = окно ПРИЁМА на момент коннекта.

Рекомендация: cipher-provider callback в muxconn (чище, чем перебор живых conn).
`Conn.SetAltProvider(func() []*crypto.Cipher)`; decryptFrame при пустом latched
берёт `c.altProvider()` (с секундным кешем). Для тип1 провайдер возвращает
статичный срез.

---

## ПОРЯДОК

1. Части 2–4 (core, тип1) → сборка+тест → коммит → деплой OFF (инертно) → проверка
   инстансов/подписки.
2. Часть 5 (manager, тип1: конфиг+API+UI+env-передача статичного alt) → деплой OFF.
3. Приёмка юзером: вкл тип1 для тестового клиента, проверить orig (разрешённый OK,
   неразрешённый reject), рандомизированный ключ (вписать вручную → OK).
4. Часть 6 (тип2 посекундный) → отдельно.
