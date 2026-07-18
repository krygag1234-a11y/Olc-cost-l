#!/usr/bin/env bash
# Olc-cost-l frontend fix: автопрокрутка логов не должна «тянуть вниз», когда юзер
# листает вверх. Общий хук useStickyLogScroll (инстанс-логи, клиент-логи, фич-логи)
# при позиции у низа немедленно возобновлял «прилипание» → при частых логах юзера
# дёргало вниз. Делаем как в журналах доступа: скролл вверх — сразу пауза; возврат
# к низу — возобновление follow только через ~700мс (не мешает листать у низа).
# Idempotent. Target: manager src/main.tsx.
set -euo pipefail

MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-sticky-scroll-resume] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

if 'olcStickyResume' in t:
    print("[patch-sticky-scroll-resume] already applied")
    sys.exit(0)

old = '''function useStickyLogScroll<T extends HTMLElement>(deps: React.DependencyList, enabled = true) {
  const ref = useRef<T | null>(null);
  const stickToBottom = useRef(true);
  const onScroll = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 32;
  }, []);

  useEffect(() => {
    if (!enabled || !stickToBottom.current) return;
    window.requestAnimationFrame(() => {
      const el = ref.current;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }, deps);

  return { ref, onScroll };
}'''

new = '''function useStickyLogScroll<T extends HTMLElement>(deps: React.DependencyList, enabled = true) {
  const ref = useRef<T | null>(null);
  const stickToBottom = useRef(true);
  const olcStickyResume = useRef<number | null>(null);
  const onScroll = useCallback(() => {
    const el = ref.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 32;
    if (nearBottom) {
      // Возврат к низу — возобновляем автопрокрутку с задержкой ~700мс,
      // чтобы не дёргать вниз, пока пользователь ещё листает у низа.
      if (olcStickyResume.current) window.clearTimeout(olcStickyResume.current);
      olcStickyResume.current = window.setTimeout(() => { stickToBottom.current = true; }, 700);
    } else {
      // Листаем вверх — немедленно останавливаем автопрокрутку.
      stickToBottom.current = false;
      if (olcStickyResume.current) { window.clearTimeout(olcStickyResume.current); olcStickyResume.current = null; }
    }
  }, []);

  useEffect(() => {
    if (!enabled || !stickToBottom.current) return;
    window.requestAnimationFrame(() => {
      const el = ref.current;
      if (el) el.scrollTop = el.scrollHeight;
    });
  }, deps);

  return { ref, onScroll };
}'''

if old in t:
    t = t.replace(old, new, 1)
    f.write_text(t)
    print("[patch-sticky-scroll-resume] OK: resume-delay added to useStickyLogScroll")
else:
    print("[patch-sticky-scroll-resume] WARN: useStickyLogScroll anchor not found (golden changed?)")
PY
