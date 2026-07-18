#!/usr/bin/env bash
# Olc-cost-l frontend fix: логи — «хвост» (rolling window). При добавлении новых
# строк старые вытеснялись сверху → просматриваемая строка «уезжала» вверх и
# выделение слетало, хотя вниз уже не тянуло. Делаем отображение НАКОПИТЕЛЬНЫМ
# (append-only): olcMergeTail склеивает предыдущие строки с новым снапшотом по
# перекрытию (next = сдвинутый хвост prev + новые), дописывая только новое. Старые
# строки не двигаются, лента растёт (cap 1500). Позиция/выделение сохраняются;
# со sticky-scroll-resume — автоскролл только у низа. Применяется к логам инстанса,
# фич (tor/zapret/split/мосты) и job-логу обновления. Idempotent. Target: main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-logs-append-only] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

# 1. Хелпер olcMergeTail (после useStickyLogScroll).
if 'function olcMergeTail' not in t:
    anchor = 'function useStickyLogScroll<T extends HTMLElement>('
    helper = '''// olcMergeTail: append-only склейка предыдущих строк лога с новым снапшотом-хвостом.
// next обычно = prev, у которого срезано начало и дописаны новые строки. Находим
// наибольшее перекрытие (суффикс prev == префикс next) и дописываем только хвост,
// чтобы старые строки не «уезжали» при ротации буфера. cap ограничивает рост.
function olcMergeTail<T>(prev: T[], next: T[], key: (x: T) => string, cap = 1500): T[] {
  if (!prev || prev.length === 0) return (next || []).slice(-cap);
  if (!next || next.length === 0) return prev;
  const maxK = Math.min(prev.length, next.length);
  let overlap = 0;
  for (let k = maxK; k > 0; k--) {
    let ok = true;
    for (let i = 0; i < k; i++) {
      if (key(prev[prev.length - k + i]) !== key(next[i])) { ok = false; break; }
    }
    if (ok) { overlap = k; break; }
  }
  const merged = prev.concat(next.slice(overlap));
  return merged.length > cap ? merged.slice(-cap) : merged;
}

'''
    if anchor in t:
        t = t.replace(anchor, helper + anchor, 1); changed = True
        print("[patch-logs-append-only] added olcMergeTail helper")
    else:
        print("[patch-logs-append-only] WARN: useStickyLogScroll anchor not found")
else:
    print("[patch-logs-append-only] helper already present")

# 2. Инстанс-логи: append-only.
old = '''    const body = (await res.json()) as { logs: LogLine[] };
    setLogs(body.logs ?? []);'''
new = '''    const body = (await res.json()) as { logs: LogLine[] };
    setLogs((prev) => olcMergeTail(prev, body.logs ?? [], (x) => x.time + "|" + x.stream + "|" + x.line, 1500));'''
if 'setLogs((prev) => olcMergeTail' in t:
    print("[patch-logs-append-only] instance logs already merged")
elif old in t:
    t = t.replace(old, new, 1); changed = True
    print("[patch-logs-append-only] instance logs append-only")
else:
    print("[patch-logs-append-only] WARN: instance setLogs anchor not found")

# 3. Фич-логи (tor/zapret/split/мосты).
old2 = '''        const body = (await res.json()) as { lines?: string[]; path?: string };
        setLines(body.lines ?? []);'''
new2 = '''        const body = (await res.json()) as { lines?: string[]; path?: string };
        setLines((prev) => (String(body.path ?? "") !== "" && String(body.path ?? "") === lastFeaturePathRef.current) ? olcMergeTail(prev, body.lines ?? [], (x) => x, 1500) : (body.lines ?? []));
        lastFeaturePathRef.current = String(body.path ?? "");'''
if 'lastFeaturePathRef' in t:
    print("[patch-logs-append-only] feature logs already merged")
elif old2 in t:
    t = t.replace(old2, new2, 1); changed = True
    # объявить ref рядом с состоянием lines
    t = t.replace(
        'const [lines, setLines] = useState<string[]>([]);',
        'const [lines, setLines] = useState<string[]>([]);\n  const lastFeaturePathRef = useRef<string>("");',
        1)
    print("[patch-logs-append-only] feature logs append-only (reset on path change)")
else:
    print("[patch-logs-append-only] WARN: feature setLines anchor not found")

# 4. Job-лог обновления.
old3 = '''          const lj = (await lr.json()) as { lines?: string[] };
          setLogLines(lj.lines ?? []);'''
new3 = '''          const lj = (await lr.json()) as { lines?: string[] };
          setLogLines((prev) => olcMergeTail(prev, lj.lines ?? [], (x) => x, 1500));'''
if 'setLogLines((prev) => olcMergeTail' in t:
    print("[patch-logs-append-only] job log already merged")
elif old3 in t:
    t = t.replace(old3, new3, 1); changed = True
    print("[patch-logs-append-only] job log append-only")
else:
    print("[patch-logs-append-only] WARN: job setLogLines anchor not found")

if changed:
    f.write_text(t)
    print("[patch-logs-append-only] OK: main.tsx updated")
else:
    print("[patch-logs-append-only] no changes (idempotent)")
PY
