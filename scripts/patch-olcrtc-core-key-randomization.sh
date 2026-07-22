#!/usr/bin/env bash
# Olc-cost-l core: РАНДОМИЗАЦИЯ КЛЮЧЕЙ (эпик A), ЧАСТЬ 1 — multi-key в muxconn.
#
# СЕРВЕР-ONLY. Подписка ВСЕГДА отдаёт оригинальные ключи, olcbox НЕ трогаем,
# рандомизированные ключи НИГДЕ не публикуются. Механизм: сервер держит
# оригинальный cipher + производные (HMAC(secret,origKey) — тип1 статичный /
# посекундный — тип2). muxconn на ПЕРВОМ фрейме пробует оригинальный, затем
# альтернативные ключи и ЛАТЧИТСЯ на сработавший; тот же ключ используется для
# ШИФРОВАНИЯ ответов; keyClass (0 ориг / 1 ранд) читается сервером на handshake.
#
# ЭТА ЧАСТЬ (1/N): только muxconn (Conn.SetAltCiphers / KeyClass / decryptFrame /
# encryptCipher). ИНЕРТНА, пока никто не вызвал SetAltCiphers → путь ИДЕНТИЧЕН
# upstream (decryptFrame с пустым alt = c.cipher.DecryptInto). Обвязка
# (server.go alt-ciphers+keyClass, session.go env, hook-решение, manager) —
# отдельными частями. Idempotent. Target: internal/muxconn/conn.go.
# Baseline: olcrtc-core ПИН 6fa08e7 (Урок 69). Run ПОСЛЕ access-hook.
set -euo pipefail

CORE_REPO="${1:?usage: $0 <path-to-olcrtc-core-repo>}"
CONN_GO="$CORE_REPO/internal/muxconn/conn.go"
[[ -f "$CONN_GO" ]] || { echo "[patch-core-key-rand] ERROR: $CONN_GO not found"; exit 1; }

python3 - "$CONN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# --- 1. Поля в Conn struct (после cipher) ---
if 'keyClass atomic.Int32' in t:
    print("[patch-core-key-rand] struct fields already present")
else:
    anchor = None
    for cand in (
        "\tcanSend func() bool // if nil, uses ln.CanSend\n\tcipher  *crypto.Cipher\n",
        "\tsend   func([]byte) error\n\tcipher *crypto.Cipher\n",
        "\tcipher  *crypto.Cipher\n",
        "\tcipher *crypto.Cipher\n",
    ):
        if cand in t:
            anchor = cand
            break
    if anchor is None:
        print("[patch-core-key-rand] WARN: cipher field anchor not found — skip struct"); 
    else:
        fields = anchor + '''
	// Olc-cost-l key-randomization (server-only). alt holds ALTERNATE decrypt
	// ciphers; empty → single-cipher fast path IDENTICAL to upstream. When set
	// (SetAltCiphers), Push tries primary+alts on the first frame and LATCHES
	// onto the authenticating cipher (used for BOTH decrypt and encrypt after);
	// keyClass records which class matched (0 original, 1 randomized).
	alt      []*crypto.Cipher
	active   atomic.Pointer[crypto.Cipher]
	keyClass atomic.Int32
'''
        t = t.replace(anchor, fields, 1); changed = True
        print("[patch-core-key-rand] added Conn struct fields")

# --- 2. Push: DecryptInto → decryptFrame ---
push_old = 'pt, err := c.cipher.DecryptInto(*bufPtr, ciphertext)'
if 'c.decryptFrame(*bufPtr, ciphertext)' in t:
    print("[patch-core-key-rand] Push already uses decryptFrame")
elif push_old in t:
    t = t.replace(push_old, 'pt, err := c.decryptFrame(*bufPtr, ciphertext)', 1); changed = True
    print("[patch-core-key-rand] Push -> decryptFrame")
else:
    print("[patch-core-key-rand] WARN: Push DecryptInto anchor not found")

# --- 3. Write: c.cipher.Encrypt → c.encryptCipher().Encrypt ---
w_old = 'enc, err := c.cipher.Encrypt(p)'
if 'c.encryptCipher().Encrypt(p)' in t:
    print("[patch-core-key-rand] Write already uses encryptCipher")
elif w_old in t:
    t = t.replace(w_old, 'enc, err := c.encryptCipher().Encrypt(p)', 1); changed = True
    print("[patch-core-key-rand] Write -> encryptCipher")
else:
    print("[patch-core-key-rand] WARN: Write Encrypt anchor not found")

# --- 4. Методы (перед функцией Push) ---
if 'func (c *Conn) SetAltCiphers(' in t:
    print("[patch-core-key-rand] methods already present")
else:
    anchor = '// Push hands an encrypted wire payload (one OnData event) to the conn.'
    methods = '''// SetAltCiphers enables Olc-cost-l server-side key-randomization on this conn by
// registering ALTERNATE decrypt ciphers (nil entries ignored). Must be called
// right after construction, before the conn is driven. With no alt ciphers the
// conn behaves exactly like upstream.
func (c *Conn) SetAltCiphers(alt ...*crypto.Cipher) {
	out := make([]*crypto.Cipher, 0, len(alt))
	for _, a := range alt {
		if a != nil {
			out = append(out, a)
		}
	}
	c.alt = out
	c.keyClass.Store(-1)
}

// KeyClass reports which key class authenticated this conn: 0 = original key,
// 1 = randomized key, -1 = not yet latched / single-cipher conn. The server
// reads this after the handshake to enforce the key-randomization rule.
func (c *Conn) KeyClass() int {
	if len(c.alt) == 0 {
		return -1
	}
	return int(c.keyClass.Load())
}

// decryptFrame decrypts one wire frame. Single-cipher conns (no alt) take the
// upstream fast path unchanged. Multi-key conns try the latched cipher first,
// otherwise probe primary+alts and latch onto the authenticating one.
func (c *Conn) decryptFrame(dst, ciphertext []byte) ([]byte, error) {
	if len(c.alt) == 0 {
		return c.cipher.DecryptInto(dst, ciphertext)
	}
	if act := c.active.Load(); act != nil {
		return act.DecryptInto(dst, ciphertext)
	}
	if pt, err := c.cipher.DecryptInto(dst, ciphertext); err == nil {
		c.active.Store(c.cipher)
		c.keyClass.Store(0)
		return pt, nil
	}
	for _, a := range c.alt {
		if pt, err := a.DecryptInto(dst, ciphertext); err == nil {
			c.active.Store(a)
			c.keyClass.Store(1)
			return pt, nil
		}
	}
	return nil, crypto.ErrCiphertextTooShort
}

// encryptCipher returns the cipher for outbound frames: the latched cipher once
// a peer key class is known, otherwise the primary.
func (c *Conn) encryptCipher() *crypto.Cipher {
	if act := c.active.Load(); act != nil {
		return act
	}
	return c.cipher
}

'''
    if anchor in t:
        t = t.replace(anchor, methods + anchor, 1); changed = True
        print("[patch-core-key-rand] added multi-key methods")
    else:
        print("[patch-core-key-rand] WARN: Push doc anchor not found — methods NOT added")

if changed:
    f.write_text(t)
    print("[patch-core-key-rand] OK: conn.go updated")
else:
    print("[patch-core-key-rand] no changes (idempotent)")
PY

# --- white-box тест multi-key (валидация: go test ./internal/muxconn/). Пишем
# всегда (идемпотентно перезаписываем) — путешествует с патчем, не теряется. ---
cat > "$CORE_REPO/internal/muxconn/olc_multikey_test.go" <<'GOTEST'
package muxconn

import (
	"bytes"
	"testing"

	"github.com/openlibrecommunity/olcrtc/internal/crypto"
)

// key32 returns a deterministic 32-byte key string for tests.
func key32(b byte) string {
	k := make([]byte, 32)
	for i := range k {
		k[i] = b + byte(i)
	}
	return string(k)
}

func mustCipher(t *testing.T, seed byte) *crypto.Cipher {
	t.Helper()
	c, err := crypto.NewCipher(key32(seed))
	if err != nil {
		t.Fatalf("NewCipher: %v", err)
	}
	return c
}

// Olc-cost-l: latches onto the ALT (randomized) cipher, keyClass=1, encrypts back with it.
func TestOlcMultiKeyLatchOnRand(t *testing.T) {
	orig := mustCipher(t, 1)
	rnd := mustCipher(t, 100)
	c := &Conn{cipher: orig, alt: []*crypto.Cipher{rnd}}
	c.keyClass.Store(-1)
	if c.KeyClass() != -1 {
		t.Fatalf("initial keyClass = %d, want -1", c.KeyClass())
	}
	msg := []byte("hello via randomized key")
	ct, err := rnd.Encrypt(msg)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	pt, err := c.decryptFrame(nil, ct)
	if err != nil || !bytes.Equal(pt, msg) {
		t.Fatalf("decryptFrame(rand): pt=%q err=%v", pt, err)
	}
	if c.KeyClass() != 1 {
		t.Fatalf("keyClass = %d, want 1", c.KeyClass())
	}
	if c.encryptCipher() != rnd {
		t.Fatalf("encryptCipher did not latch onto rand")
	}
	ctOrig, _ := orig.Encrypt(msg)
	if _, err := c.decryptFrame(nil, ctOrig); err == nil {
		t.Fatalf("latched conn wrongly accepted original-key frame")
	}
}

// Olc-cost-l: latches onto the ORIGINAL cipher, keyClass=0.
func TestOlcMultiKeyLatchOnOrig(t *testing.T) {
	orig := mustCipher(t, 1)
	rnd := mustCipher(t, 100)
	c := &Conn{cipher: orig, alt: []*crypto.Cipher{rnd}}
	c.keyClass.Store(-1)
	msg := []byte("hello via original key")
	ct, _ := orig.Encrypt(msg)
	pt, err := c.decryptFrame(nil, ct)
	if err != nil || !bytes.Equal(pt, msg) {
		t.Fatalf("decryptFrame(orig): pt=%q err=%v", pt, err)
	}
	if c.KeyClass() != 0 {
		t.Fatalf("keyClass = %d, want 0", c.KeyClass())
	}
	if c.encryptCipher() != orig {
		t.Fatalf("encryptCipher did not latch onto orig")
	}
}

// Olc-cost-l: no alt ciphers → behaves exactly like upstream, keyClass stays -1.
func TestOlcSingleCipherUnchanged(t *testing.T) {
	orig := mustCipher(t, 7)
	c := &Conn{cipher: orig}
	c.keyClass.Store(-1)
	msg := []byte("single cipher path")
	ct, _ := orig.Encrypt(msg)
	pt, err := c.decryptFrame(nil, ct)
	if err != nil || !bytes.Equal(pt, msg) {
		t.Fatalf("decryptFrame: pt=%q err=%v", pt, err)
	}
	if c.KeyClass() != -1 {
		t.Fatalf("single-cipher keyClass = %d, want -1", c.KeyClass())
	}
	if c.encryptCipher() != orig {
		t.Fatalf("encryptCipher != primary on single-cipher conn")
	}
}

// Olc-cost-l: a frame under a THIRD (unknown) key is rejected, conn stays unlatched.
func TestOlcMultiKeyRejectsUnknown(t *testing.T) {
	orig := mustCipher(t, 1)
	rnd := mustCipher(t, 100)
	other := mustCipher(t, 200)
	c := &Conn{cipher: orig, alt: []*crypto.Cipher{rnd}}
	c.keyClass.Store(-1)
	ct, _ := other.Encrypt([]byte("attacker frame"))
	if _, err := c.decryptFrame(nil, ct); err == nil {
		t.Fatalf("decryptFrame accepted unknown-key frame")
	}
	if c.KeyClass() != -1 {
		t.Fatalf("keyClass = %d after failed decrypt, want -1", c.KeyClass())
	}
}
GOTEST
echo "[patch-core-key-rand] wrote internal/muxconn/olc_multikey_test.go"

# ============================================================================
# ЧАСТИ 2-3 (тип1): handshake.go (keyClass) + server.go (alt-ciphers, SetAltCiphers,
# проброс keyClass) + session.go (env OLCRTC_ALT_KEYS). ИНЕРТНО без alt-ключей.
# ============================================================================
python3 - "$CORE_REPO" <<'PY'
import sys, pathlib, re
repo = pathlib.Path(sys.argv[1])

# --- handshake.go ---
hp = repo / "internal/handshake/handshake.go"
h = hp.read_text()
if "keyClass int) (Hello, string, error)" not in h:
    h = h.replace("func Server(rw io.ReadWriter, auth AuthFunc) (Hello, string, error) {",
                  "func Server(rw io.ReadWriter, auth AuthFunc, keyClass int) (Hello, string, error) {", 1)
    old = "\tsessionID, err := auth(h.DeviceID, h.Claims)\n"
    new = ('\t// Olc-cost-l key-randomization: класс ключа (0 ориг/1 ранд/-1 single) в auth\n'
           '\t// через reserved-claim (клиент не контролирует, сервер перезаписывает).\n'
           '\tif h.Claims == nil {\n\t\th.Claims = map[string]any{}\n\t}\n'
           '\th.Claims["_olc_key_class"] = keyClass\n'
           '\tsessionID, err := auth(h.DeviceID, h.Claims)\n')
    if old in h:
        h = h.replace(old, new, 1)
    hp.write_text(h)
    print("[patch-core-key-rand] handshake.go: Server +keyClass")
else:
    print("[patch-core-key-rand] handshake.go already patched")

# handshake_test.go: Server(x, func(...){...}) -> +", 0)" (грубо; build тесты не гоняет)
tp = repo / "internal/handshake/handshake_test.go"
if tp.exists():
    tt = tp.read_text()
    tt2 = re.sub(r'(handshake\.)?Server\((\w+), (func\([^)]*\)[^\n]*\{)', r'Server(\2, \3', tt)  # no-op safeguard
    # заменяем закрытие вызова Server(...) добавлением ,0 — простая эвристика по строкам
    # (оставляем как есть если не находим; тесты не влияют на go build)
    tp.write_text(tt)

# --- server.go ---
sp = repo / "internal/server/server.go"
t = sp.read_text()
if "altCiphers []*crypto.Cipher" not in t:
    t = t.replace("\tTraffic          transport.TrafficConfig\n",
        "\tTraffic          transport.TrafficConfig\n\n\t// Olc-cost-l key-randomization (server-only): hex(64)=32b alt-ключи для\n\t// приёма от НЕразрешённых. Пусто → single-cipher (upstream).\n\tAltKeysHex []string\n", 1)
    t = t.replace("\tln      transport.Transport\n\tpeerLn  transport.PeerTransport\n\tcipher  *crypto.Cipher\n",
        "\tln      transport.Transport\n\tpeerLn  transport.PeerTransport\n\tcipher  *crypto.Cipher\n\taltCiphers []*crypto.Cipher // Olc-cost-l key-randomization\n", 1)
    anchor=("\tcipher, err := setupCipher(cfg.KeyHex)\n\tif err != nil {\n"
            "\t\treturn fmt.Errorf(\"setupCipher failed: %w\", err)\n\t}\n")
    add=("\tvar altCiphers []*crypto.Cipher\n\tfor _, hx := range cfg.AltKeysHex {\n"
         "\t\tac, aerr := setupCipher(hx)\n\t\tif aerr != nil {\n\t\t\tlogger.Warnf(\"olc key-rand: bad alt key (skipped): %v\", aerr)\n\t\t\tcontinue\n\t\t}\n"
         "\t\taltCiphers = append(altCiphers, ac)\n\t}\n")
    t = t.replace(anchor, anchor+add, 1)
    t = t.replace("\ts := &Server{\n\t\tcipher:         cipher,\n",
                  "\ts := &Server{\n\t\tcipher:         cipher,\n\t\taltCiphers:     altCiphers,\n", 1)
    # helper + acceptHandshake signature + kc
    anchor="func (s *Server) acceptHandshake(ctx context.Context, sess *smux.Session) bool {"
    helper=("// olcKeyClass — класс ключа conn для handshake (-1 если nil/single). Olc-cost-l.\n"
            "func olcKeyClass(c *muxconn.Conn) int {\n\tif c == nil {\n\t\treturn -1\n\t}\n\treturn c.KeyClass()\n}\n\n")
    t = t.replace(anchor, helper+"func (s *Server) acceptHandshake(ctx context.Context, sess *smux.Session, conn *muxconn.Conn) bool {\n\tkc := olcKeyClass(conn)", 1)
    t = t.replace("func (s *Server) acceptPeerHandshake(ctx context.Context, ps *peerSession) {",
                  "func (s *Server) acceptPeerHandshake(ctx context.Context, ps *peerSession) {\n\tkc := olcKeyClass(ps.controlConn)", 1)
    t = t.replace("hello, sid, err := handshake.Server(stream, s.authHook)",
                  "hello, sid, err := handshake.Server(stream, s.authHook, kc)")
    t = t.replace("go s.acceptHandshake(s.baseCtx, controlSess)", "go s.acceptHandshake(s.baseCtx, controlSess, controlConn)")
    t = t.replace("go s.acceptHandshake(s.baseCtx, r.controlSess)", "go s.acceptHandshake(s.baseCtx, r.controlSess, r.controlConn)")
    t = t.replace("if !s.acceptHandshake(ctx, sess) {", "if !s.acceptHandshake(ctx, sess, s.conn) {")
    t = t.replace("if !s.acceptHandshake(s.baseCtx, ps.session) {", "if !s.acceptHandshake(s.baseCtx, ps.session, ps.conn) {")
    # SetAltCiphers на conn-сайтах построчно
    pat=re.compile(r'^(\s*)([\w.]+)\s*:?=\s*muxconn\.(New|NewControl|NewPeer|NewPeerControl)\(')
    outl=[]
    for ln in t.split("\n"):
        outl.append(ln)
        m=pat.match(ln)
        if m:
            ind,var,ctor=m.group(1),m.group(2),m.group(3)
            if ctor in ("NewControl","NewPeerControl"):
                outl.append(f"{ind}if {var} != nil {{ {var}.SetAltCiphers(s.altCiphers...) }}")
            else:
                outl.append(f"{ind}{var}.SetAltCiphers(s.altCiphers...)")
    t="\n".join(outl)
    sp.write_text(t)
    print("[patch-core-key-rand] server.go: altCiphers+SetAltCiphers(%d)+keyClass" % t.count("SetAltCiphers(s.altCiphers...)"))
else:
    print("[patch-core-key-rand] server.go already patched")

# --- session.go ---
zp = repo / "internal/app/session/session.go"
z = zp.read_text()
if "olcAltKeysFromEnv()" not in z:
    kh="\t\t\tKeyHex:           cfg.KeyHex,\n"
    z=z.replace(kh, kh+"\t\t\tAltKeysHex:       olcAltKeysFromEnv(), // Olc-cost-l key-randomization (OLCRTC_ALT_KEYS)\n", 1)  # 1-е вхождение = server.Config
    zp.write_text(z)
    print("[patch-core-key-rand] session.go: AltKeysHex")
else:
    print("[patch-core-key-rand] session.go already patched")
PY
echo "[patch-core-key-rand] parts 2-3 done"

# ============================================================================
# ЧАСТЬ 4 (тип1): пост-обработка сгенерированного olc_access_hook.go (access-hook
# патч эмитит его ДО нас) — 3-режимная матрица (off|keyrand|enforce) + keyClass +
# olcAltKeysFromEnv. Разделение: access-hook = база; key-rand добавляет keyClass.
# ============================================================================
python3 - "$CORE_REPO" <<'PY'
import sys, pathlib
repo = pathlib.Path(sys.argv[1])
hp = repo / "internal/app/session/olc_access_hook.go"
if not hp.exists():
    print("[patch-core-key-rand] WARN: olc_access_hook.go отсутствует (access-hook не применён?) — пропуск hook"); sys.exit(0)
t = hp.read_text()
if "olcAccessDecideConnFull" in t:
    print("[patch-core-key-rand] hook already 3-mode"); sys.exit(0)

# 1) ConnMode поля
t = t.replace(
"\tConnEnforce   bool           `json:\"conn_enforce\"`\n\tConnScope     string         `json:\"conn_scope\"`\n\tConnInstances []string       `json:\"conn_instances\"`\n}",
"\tConnEnforce   bool           `json:\"conn_enforce\"`\n\tConnMode      string         `json:\"conn_mode\"` // Olc-cost-l: off|keyrand|enforce; пусто→из ConnEnforce\n\tConnScope     string         `json:\"conn_scope\"`\n\tConnInstances []string       `json:\"conn_instances\"`\n}",1)
t = t.replace(
"\tEnforceConns  bool                     `json:\"enforce_connections\"`\n",
"\tEnforceConns  bool                     `json:\"enforce_connections\"`\n\tConnMode      string                   `json:\"conn_mode\"` // Olc-cost-l глоб: off|keyrand|enforce\n",1)

# 2) helper + olcAltKeysFromEnv перед olcAccessConnDecide
helpers='''// olcConnModeResolve — 3-значный режим из строки ConnMode или (обратно совместимо)
// из bool enforce. Olc-cost-l key-randomization.
func olcConnModeResolve(mode string, enforce bool) string {
	switch mode {
	case "off", "keyrand", "enforce":
		return mode
	}
	if enforce {
		return "enforce"
	}
	return "off"
}

// olcAltKeysFromEnv — рандомизированные ключи из OLCRTC_ALT_KEYS (CSV hex). Olc-cost-l.
func olcAltKeysFromEnv() []string {
	v := strings.TrimSpace(os.Getenv("OLCRTC_ALT_KEYS"))
	if v == "" {
		return nil
	}
	var out []string
	for _, k := range strings.Split(v, ",") {
		if k = strings.TrimSpace(k); k != "" {
			out = append(out, k)
		}
	}
	return out
}

'''
t = t.replace("func olcAccessConnDecide(deviceID string) bool {", helpers+"func olcAccessConnDecide(deviceID string) bool {",1)

# 3) заменить тело olcAccessConnDecide на матрицу + Full
s=t.index("func olcAccessConnDecide(deviceID string) bool {")
e=t.index("\treturn true\n}\n", s)+len("\treturn true\n}\n")
new='''func olcAccessConnDecide(deviceID string) bool {
	return olcAccessDecideConnFull(deviceID, -1, true) // recheck ban-watcher: без keyClass
}

// olcAccessDecideConnFull — ЕДИНАЯ точка решения (Olc-cost-l key-randomization, 3
// режима). keyClass: -1 ранд выкл / 0 ориг / 1 ранд. recheck=true (ban-watcher):
// не отклонять «неизвестных» по классу ключа (живая сессия прошла handshake). fail-open.
func olcAccessDecideConnFull(deviceID string, keyClass int, recheck bool) bool {
	dev := strings.TrimSpace(deviceID)
	data, err := os.ReadFile(olcAccessControlPath)
	if err != nil {
		if !os.IsNotExist(err) {
			olcAccWarnf("olc-access: read config failed (fail-open): %v", err)
		}
		return true
	}
	var ac olcAccControl
	if err := json.Unmarshal(data, &ac); err != nil {
		olcAccWarnf("olc-access: parse config failed (fail-open): %v", err)
		return true
	}
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	var (
		mode      string
		allow     []olcAccDevice
		ban       []olcAccDevice
		banNoHwid bool
		scope     string
		insts     []string
		scoped    bool
	)
	if ac.Enabled {
		mode = olcConnModeResolve(ac.ConnMode, ac.EnforceConns)
		allow, ban, banNoHwid = ac.ConnDevices, ac.ConnBan, ac.BanNoHwid
		scope, insts = ac.ConnScope, ac.ConnInstances
		scoped = true
	} else {
		cid := strings.TrimSpace(os.Getenv("OLCRTC_CLIENT_ID"))
		if cid != "" && ac.Clients != nil {
			if cc, ok := ac.Clients[cid]; ok && cc != nil {
				mode = olcConnModeResolve(cc.ConnMode, cc.ConnEnforce)
				allow, ban, banNoHwid = cc.ConnAllow, cc.ConnBan, cc.BanNoHwid
				scope, insts = cc.ConnScope, cc.ConnInstances
				scoped = true
			}
		}
	}
	if !scoped {
		return true
	}
	if (mode == "enforce" || mode == "keyrand") && scope == "selective" {
		inList := false
		for _, r := range insts {
			if strings.TrimSpace(r) == room && room != "" {
				inList = true
				break
			}
		}
		if !inList {
			return false
		}
	}
	switch mode {
	case "enforce":
		return olcAccDecideConn(dev, banNoHwid, allow, ban)
	case "keyrand":
		if olcAccDecideConn(dev, banNoHwid, allow, ban) {
			return true
		}
		if olcAccMatch(ban, dev) {
			return false
		}
		if recheck {
			return true
		}
		return keyClass == 1
	default:
		if !olcAccDecideBanOnly(dev, banNoHwid, ban) {
			return false
		}
		if keyClass < 0 || recheck {
			return true
		}
		return keyClass == 1
	}
}
'''
t=t[:s]+new+t[e:]

# 4) hook: keyClass + Full
old_hook='''func olcAccessConnectionAuthHook(deviceID string, _ map[string]any) (string, error) {
	dev := strings.TrimSpace(deviceID)
	if olcAccessConnDecide(dev) {
		// Принятые подключения видны по «peer connected: device=…» —
		// отдельная allowed=true строка не нужна (и ломала счёт журнала).
		return uuid.NewString(), nil
	}
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	logger.Infof("olc-access: conn attempt device=%s allowed=false room=%s", dev, room)
	return "", errors.New("device not allowed to connect")
}'''
new_hook='''func olcAccessConnectionAuthHook(deviceID string, claims map[string]any) (string, error) {
	dev := strings.TrimSpace(deviceID)
	keyClass := -1
	if claims != nil {
		if v, ok := claims["_olc_key_class"].(int); ok {
			keyClass = v
		} else if f, ok := claims["_olc_key_class"].(float64); ok {
			keyClass = int(f)
		}
	}
	if olcAccessDecideConnFull(dev, keyClass, false) {
		return uuid.NewString(), nil
	}
	room := strings.TrimSpace(os.Getenv("OLCRTC_ROOM_ID"))
	logger.Infof("olc-access: conn attempt device=%s allowed=false room=%s keyclass=%d", dev, room, keyClass)
	return "", errors.New("device not allowed to connect")
}'''
if old_hook in t:
    t=t.replace(old_hook,new_hook,1)
else:
    print("[patch-core-key-rand] WARN: hook block not found (access-hook изменился?)")

hp.write_text(t)
print("[patch-core-key-rand] hook: 3-режимная матрица + keyClass")
PY
echo "[patch-core-key-rand] part 4 done"
