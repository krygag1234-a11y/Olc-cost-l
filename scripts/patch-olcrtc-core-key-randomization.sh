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
