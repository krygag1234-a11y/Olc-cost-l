#!/usr/bin/env bash
# Add an explicit HTTP/IP -> verified HTTPS Jitsi domain helper to create/edit forms.
set -euo pipefail

MAIN_TSX="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/src/main.tsx}"
[[ -f "$MAIN_TSX" ]] || exit 0
grep -q 'OLC_JITSI_HTTPS_DISCOVERY_UI_V1' "$MAIN_TSX" && { echo "[patch-panel-jitsi-https-discovery] already applied"; exit 0; }

python3 - "$MAIN_TSX" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

component_anchor = "function Socks5ProxyFields({"
if text.count(component_anchor) != 1:
    raise SystemExit("[patch-panel-jitsi-https-discovery] component anchor changed")

component = r'''/* OLC_JITSI_HTTPS_DISCOVERY_UI_V1 */
type JitsiHTTPSCandidate = {
  domain: string;
  url: string;
  confidence: string;
  evidence: string[];
};

type JitsiHTTPSDiscoveryResult = {
  ok: boolean;
  source_ip?: string;
  summary: string;
  candidates: JitsiHTTPSCandidate[];
  tried: number;
};

function numericJitsiIP(value: string): string | null {
  const raw = value.trim();
  if (!raw) return null;
  try {
    const parsed = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : `http://${raw}`);
    const host = parsed.hostname.replace(/^\[|\]$/g, "");
    if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) {
      const parts = host.split(".").map(Number);
      return parts.every((part) => part >= 0 && part <= 255) ? host : null;
    }
    return /^[0-9a-f:]+$/i.test(host) && host.includes(":") ? host : null;
  } catch {
    return null;
  }
}

function JitsiHTTPSDiscovery({ server, onUse }: { server: string; onUse: (server: string) => void }) {
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<JitsiHTTPSDiscoveryResult | null>(null);
  const [error, setError] = useState("");
  const ip = numericJitsiIP(server);

  useEffect(() => {
    setResult(null);
    setError("");
  }, [server]);

  const discover = useCallback(async () => {
    if (!ip) return;
    setBusy(true);
    setError("");
    try {
      const response = await request(`/api/jitsi/discover-https?server=${encodeURIComponent(server.trim())}`, { cache: "no-store" });
      const body = (await response.json()) as JitsiHTTPSDiscoveryResult;
      setResult(body);
      if (!response.ok) setError(body.summary || `HTTP ${response.status}`);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }, [ip, server]);

  if (!ip) return null;
  return (
    <div className="grid gap-2 rounded-md border border-border bg-background/50 p-3 text-xs">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <div className="font-medium text-foreground">Помощник Jitsi HTTP IP → HTTPS domain:443</div>
          <div className="mt-0.5 text-[11px] text-muted-foreground">Проверяет сертификат, DNS и Jitsi endpoints. Server меняется только после вашего выбора; Room ID сохраняется.</div>
        </div>
        <button
          type="button"
          className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50"
          disabled={busy}
          onClick={() => void discover()}
        >
          {busy ? "Проверяю…" : "Найти HTTPS-домен"}
        </button>
      </div>
      {error ? <p className="text-destructive">{error}</p> : null}
      {result ? (
        <div className="grid gap-2">
          <p className={result.ok ? "text-green-600" : "text-amber-600"}>{result.summary} · проверено кандидатов: {result.tried}</p>
          {result.candidates.map((candidate) => (
            <div key={candidate.domain} className="grid gap-1 rounded-md border border-green-500/30 bg-green-500/5 p-2">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-mono text-green-600">{candidate.url}</span>
                <button
                  type="button"
                  className="inline-flex h-7 items-center rounded-md border border-green-500/40 bg-green-500/10 px-2 text-[11px] text-green-600 hover:bg-green-500/20"
                  onClick={() => onUse(candidate.url)}
                >
                  Использовать
                </button>
              </div>
              {candidate.evidence.slice(0, 4).map((item) => <div key={item} className="text-[10px] text-muted-foreground">• {item}</div>)}
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

'''
text = text.replace(component_anchor, component + component_anchor, 1)

create_old = '''      {location.carrier === "jitsi" ? (
        <label className="grid gap-2 text-sm text-muted-foreground">
          Jitsi Server
          <input
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={location.jitsi_instance}
            onChange={(event) => set({ jitsi_instance: event.target.value })}
            placeholder={DEFAULT_JITSI_INSTANCE}
          />
          <p className="text-[11px] text-muted-foreground">Можно вставить полную ссылку сюда или в Room ID — поля разделятся автоматически.</p>
        </label>
      ) : null}
'''
create_new = '''      {location.carrier === "jitsi" ? (
        <div className="grid gap-2 text-sm text-muted-foreground">
          <span>Jitsi Server</span>
          <input
            className="h-10 rounded-md border border-border bg-background px-3 text-foreground outline-none focus:border-primary"
            value={location.jitsi_instance}
            onChange={(event) => set({ jitsi_instance: event.target.value })}
            placeholder={DEFAULT_JITSI_INSTANCE}
          />
          <p className="text-[11px] text-muted-foreground">Можно вставить полную ссылку сюда или в Room ID — поля разделятся автоматически.</p>
          <JitsiHTTPSDiscovery server={location.jitsi_instance} onUse={(jitsi_instance) => set({ jitsi_instance })} />
        </div>
      ) : null}
'''
if text.count(create_old) != 1:
    raise SystemExit("[patch-panel-jitsi-https-discovery] create Jitsi Server field changed")
text = text.replace(create_old, create_new, 1)

edit_old = '''            {location.carrier === "jitsi" ? (
              <label className="grid gap-2 text-sm text-muted-foreground">
                Jitsi Server
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.jitsi_instance}
                  onChange={(event) => setLocation(index, { jitsi_instance: event.target.value })}
                  placeholder={DEFAULT_JITSI_INSTANCE}
                />
                <p className="text-[11px] text-muted-foreground">Полную ссылку можно вставить в любое из двух полей.</p>
              </label>
            ) : null}
'''
edit_new = '''            {location.carrier === "jitsi" ? (
              <div className="grid gap-2 text-sm text-muted-foreground">
                <span>Jitsi Server</span>
                <input
                  className="h-10 rounded-md border border-border bg-card px-3 text-foreground outline-none focus:border-primary"
                  value={location.jitsi_instance}
                  onChange={(event) => setLocation(index, { jitsi_instance: event.target.value })}
                  placeholder={DEFAULT_JITSI_INSTANCE}
                />
                <p className="text-[11px] text-muted-foreground">Полную ссылку можно вставить в любое из двух полей.</p>
                <JitsiHTTPSDiscovery server={location.jitsi_instance} onUse={(jitsi_instance) => setLocation(index, { jitsi_instance })} />
              </div>
            ) : null}
'''
if text.count(edit_old) != 1:
    raise SystemExit("[patch-panel-jitsi-https-discovery] edit Jitsi Server field changed")
text = text.replace(edit_old, edit_new, 1)

path.write_text(text)
print("[patch-panel-jitsi-https-discovery] ok")
PY
