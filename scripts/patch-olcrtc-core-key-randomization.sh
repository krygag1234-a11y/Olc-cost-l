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
