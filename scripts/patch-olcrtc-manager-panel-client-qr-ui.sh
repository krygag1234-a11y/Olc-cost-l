#!/usr/bin/env bash
# Olc-cost-l UI (Этап 4 эпика «Типы рандомизации»): кнопка «Sub» → «Qr» + модалка Qr.
#   - карточка клиента: кнопка "📱 Qr" вместо сломанной "Sub";
#   - ClientQrModal (Modal + img api.qrserver.com):
#       OFF = 1 QR + URL (центрирован, без пустого места под 2-й);
#       ON тип1 = 2 блока (оригинал + рандомная рабочая ссылка);
#       ON тип2 = оригинал + «Ротация»: декоративный СИЛЬНО заблюренный QR (статичный QR
#         для динамического URL невозможен) + подпись + URL, тикающий КАЖДУЮ СЕКУНДУ
#         (поллинг /api/clients/:id/subscription-url) — видно смену client_id;
#         без контроля доступа — доп. амбер-предупреждение.
#   Кастомный путь /sub/ учитывается (path из настроек + серверный subscription-url).
# Idempotent. Target: main.tsx. Run ПОСЛЕ randomization-type-ui.
set -euo pipefail
MAIN_TSX="${1:?usage: $0 <path-to-main.tsx>}"
[[ -f "$MAIN_TSX" ]] || { echo "[patch-client-qr-ui] ERROR: $MAIN_TSX not found"; exit 1; }

python3 - "$MAIN_TSX" <<'PY'
import sys, pathlib, re
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False
def rep(old, new, tag):
    global t, changed
    if new in t:
        print(f"[client-qr-ui] {tag}: already applied"); return
    if old not in t:
        print(f"[client-qr-ui] WARN {tag}: anchor NOT FOUND"); return
    t = t.replace(old, new, 1); changed = True
    print(f"[client-qr-ui] {tag}: ok")

comp = '''function ClientQrModal({ client, path, globalRandomizationEnabled, globalAccessEnabled, accessConfigured, onClose }: { client: any; path?: string; globalRandomizationEnabled?: boolean; globalAccessEnabled?: boolean; accessConfigured?: boolean; onClose: () => void }) {
  const origin = window.location.origin;
  const p = (path && path.trim().replace(/^\\/+|\\/+$/g, "")) || "sub";
  const rnd = client.randomization || {};
  const enabled = !!(rnd.enabled || globalRandomizationEnabled);
  const rtype = rnd.rand_type || 1;
  const origUrl = `${origin}/${p}/${encodeURIComponent(client.client_id)}/`;
  const staticUrl = rnd.randomized_id ? `${origin}/${p}/${rnd.randomized_id}/` : "";
  const [rotUrl, setRotUrl] = useState("");
  useEffect(() => {
    if (!(enabled && rtype === 2)) return;
    let stop = false;
    const tick = () => {
      void fetch(`/api/clients/${encodeURIComponent(client.client_id)}/subscription-url`, { cache: "no-store" })
        .then((r) => r.json())
        .then((b: any) => { if (!stop && b && b.url) setRotUrl(`${origin}${b.url}`); })
        .catch(() => {});
    };
    tick();
    const id = window.setInterval(tick, 1000);
    return () => { stop = true; window.clearInterval(id); };
  }, []);
  const qr = (data: string) => `https://api.qrserver.com/v1/create-qr-code/?size=256x256&data=${encodeURIComponent(data)}`;
  const copy = (s: string) => { if (s) void navigator.clipboard.writeText(s); };
  const type2NoAccess = enabled && rtype === 2 && !globalAccessEnabled && !accessConfigured;
  const stdBlock = (k: string, title: string, url: string, note?: string) => (
    <div key={k} className="grid w-full max-w-xs justify-items-center gap-2 rounded-md border border-border p-3">
      <div className="text-center text-xs font-semibold text-foreground">{title}</div>
      <img className="h-44 w-44 rounded-md bg-white p-2" src={qr(url || origUrl)} alt="QR" />
      {note && <div className="max-w-[16rem] text-center text-[10px] leading-tight text-muted-foreground">{note}</div>}
      <div className="max-w-full break-all rounded border border-border bg-background p-2 font-mono text-[10px] text-muted-foreground">{url || "—"}</div>
      <button type="button" className="h-8 rounded-md border border-border bg-muted px-3 text-xs hover:bg-muted/80 disabled:opacity-50" disabled={!url} onClick={() => copy(url)}>Копировать</button>
    </div>
  );
  const rotBlock = () => (
    <div key="rot" className="grid w-full max-w-xs justify-items-center gap-2 rounded-md border border-border p-3">
      <div className="text-center text-xs font-semibold text-foreground">Ротация (меняется каждую секунду)</div>
      <div className="relative h-44 w-44">
        <img className="pointer-events-none h-44 w-44 select-none rounded-md bg-white p-2 opacity-70 blur-[10px]" src={qr(origUrl)} alt="" aria-hidden="true" />
        <div className="absolute inset-0 grid place-items-center p-3 text-center text-[10px] font-semibold text-foreground/80">статический QR при динамическом хэше недоступен</div>
      </div>
      <div className="max-w-full break-all rounded border border-border bg-background p-2 font-mono text-[10px] text-amber-500">{rotUrl || "…"}</div>
      <div className="text-center text-[10px] text-muted-foreground">client_id меняется каждую секунду</div>
      {type2NoAccess && <div className="max-w-[16rem] text-center text-[10px] leading-tight text-amber-500">Тип 2 без контроля доступа: пользоваться нереально. Настройте контроль доступа (⚙).</div>}
    </div>
  );
  const blocks: any[] = [];
  if (!enabled) {
    blocks.push(stdBlock("o", "Ссылка-подписка", origUrl));
  } else {
    blocks.push(stdBlock("o", "Оригинальный client_id", origUrl, rtype === 2 ? "Работает только для разрешённых устройств (контроль доступа)" : "При рандомизации прямой доступ по client_id заблокирован"));
    if (rtype === 1) blocks.push(stdBlock("s", "Рандомная (рабочая) ссылка", staticUrl, "Постоянный случайный хэш"));
    else blocks.push(rotBlock());
  }
  return (
    <Modal title={`QR — ${client.client_id}`} onClose={onClose}>
      <div className={blocks.length > 1 ? "grid gap-3 p-4 sm:grid-cols-2" : "grid justify-items-center gap-3 p-4"}>{blocks}</div>
    </Modal>
  );
}

function App() {'''
rep("function App() {", comp, "ClientQrModal component")

# 2. Состояние subQrTarget
rep(
"  const [randTypeTarget, setRandTypeTarget] = useState<string | null>(null);",
"  const [randTypeTarget, setRandTypeTarget] = useState<string | null>(null);\n  const [subQrTarget, setSubQrTarget] = useState<string | null>(null);",
"subQrTarget state")

# 3. Кнопка «Sub» → «Qr»
rep(
'''                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        onClick={() => copySubscription(client.client_id)}
                      >
                        {t("subBtn")}
                      </button>''',
'''                      <button
                        className="inline-flex h-8 items-center gap-2 rounded-md border border-border px-2 text-sm hover:bg-muted disabled:opacity-60"
                        disabled={busy}
                        title="QR и ссылки подписки"
                        onClick={() => setSubQrTarget(client.client_id)}
                      >
                        📱 Qr
                      </button>''',
"Sub button -> Qr")

# 4. Рендер модалки Qr (после RandTypeModal)
rep(
'''      {randTypeTarget && (
        <RandTypeModal
          clientId={randTypeTarget}
          onClose={() => setRandTypeTarget(null)}
          onChoose={(ty) => { const cid = randTypeTarget; setRandTypeTarget(null); void toggleRandomization(cid, false, ty); }}
        />
      )}''',
'''      {randTypeTarget && (
        <RandTypeModal
          clientId={randTypeTarget}
          onClose={() => setRandTypeTarget(null)}
          onChoose={(ty) => { const cid = randTypeTarget; setRandTypeTarget(null); void toggleRandomization(cid, false, ty); }}
        />
      )}
      {subQrTarget && (() => {
        const c = (state?.clients || []).find((x: any) => x.client_id === subQrTarget);
        if (!c) return null;
        return (
          <ClientQrModal
            client={c}
            path={currentSubscriptionPath}
            globalRandomizationEnabled={globalRandomizationEnabled}
            globalAccessEnabled={globalAccessEnabled}
            accessConfigured={!!accessCfg[subQrTarget]}
            onClose={() => setSubQrTarget(null)}
          />
        );
      })()}''',
"ClientQrModal render")

if changed:
    f.write_text(t)
print("[patch-client-qr-ui] done")
PY
