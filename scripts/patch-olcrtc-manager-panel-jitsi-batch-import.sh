#!/usr/bin/env bash
# Add batch HTTP-IP file import to the Jitsi HTTPS discovery helper.
set -euo pipefail

target="${1:-/tmp/olcrtc-manager-panel/src/main.tsx}"
[[ -f "$target" ]] || { echo "[jitsi-batch-import] target not found: $target" >&2; exit 1; }

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "OLC_JITSI_BATCH_IMPORT_V1"
if marker in text:
    print(f"[jitsi-batch-import] already applied: {path}")
    raise SystemExit(0)

def one(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"[jitsi-batch-import] {label}: expected one match, got {count}")
    text = text.replace(old, new, 1)

component = text.index("function JitsiHTTPSDiscovery(")
batch_types = r'''type JitsiBatchItem = {
  source: string;
  status: "pending" | "checking" | "done" | "error";
  result?: JitsiHTTPSDiscoveryResult;
  error?: string;
};

function parseJitsiHTTPIPFile(text: string): { items: JitsiBatchItem[]; httpsSkipped: number; invalidSkipped: number; duplicatesSkipped: number } {
  const seen = new Set<string>();
  const items: JitsiBatchItem[] = [];
  let httpsSkipped = 0;
  let invalidSkipped = 0;
  let duplicatesSkipped = 0;
  for (const token of text.split(/[,;\r\n]+/)) {
    const raw = token.trim().replace(/^["']|["']$/g, "");
    if (!raw) continue;
    if (/^https:\/\//i.test(raw)) { httpsSkipped += 1; continue; }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(raw) && !/^http:\/\//i.test(raw)) { invalidSkipped += 1; continue; }
    try {
      const parsed = new URL(/^http:\/\//i.test(raw) ? raw : `http://${raw}`);
      const ip = numericJitsiIP(parsed.href);
      if (!ip) { invalidSkipped += 1; continue; }
      const host = ip.includes(":") ? `[${ip}]` : ip;
      const source = `http://${host}${parsed.port ? `:${parsed.port}` : ""}`;
      if (seen.has(source)) { duplicatesSkipped += 1; continue; }
      seen.add(source);
      items.push({ source, status: "pending" });
    } catch { invalidSkipped += 1; }
  }
  return { items, httpsSkipped, invalidSkipped, duplicatesSkipped };
}

'''
text = text[:component] + batch_types + text[component:]

one(
'''  const [error, setError] = useState("");
  const ip = numericJitsiIP(source);''',
'''  const [error, setError] = useState("");
  const [batch, setBatch] = useState<JitsiBatchItem[]>([]);
  const [batchBusy, setBatchBusy] = useState(false);
  const [batchNote, setBatchNote] = useState("");
  const [batchExpanded, setBatchExpanded] = useState(false);
  const ip = numericJitsiIP(source);''',
"batch state",
)

methods = r'''

  const loadBatchFile = useCallback(async (file: File | undefined) => {
    if (!file) return;
    if (file.size > 1024 * 1024) {
      setBatch([]);
      setBatchNote("Файл больше 1 MiB — выберите меньший список");
      return;
    }
    const parsed = parseJitsiHTTPIPFile(await file.text());
    setBatch(parsed.items);
    setBatchExpanded(parsed.items.length > 0 && parsed.items.length <= 5);
    setBatchNote(`Принято HTTP IP: ${parsed.items.length} · пропущено HTTPS: ${parsed.httpsSkipped} · некорректных: ${parsed.invalidSkipped} · дублей: ${parsed.duplicatesSkipped}`);
  }, []);

  const discoverBatch = useCallback(async () => {
    if (!batch.length || batchBusy) return;
    setBatchBusy(true);
    setBatch((current) => current.map((item) => ({ ...item, status: "pending", result: undefined, error: undefined })));
    let cursor = 0;
    const worker = async () => {
      while (true) {
        const index = cursor++;
        if (index >= batch.length) return;
        const item = batch[index];
        setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: "checking" } : entry));
        try {
          const response = await request(`/api/jitsi/discover-https?server=${encodeURIComponent(item.source)}`, { cache: "no-store" });
          const body = (await response.json()) as JitsiHTTPSDiscoveryResult;
          setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: response.ok ? "done" : "error", result: body, error: response.ok ? undefined : body.summary || `HTTP ${response.status}` } : entry));
        } catch (cause) {
          const message = cause instanceof Error ? cause.message : String(cause);
          setBatch((current) => current.map((entry, i) => i === index ? { ...entry, status: "error", error: message } : entry));
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(3, batch.length) }, () => worker()));
    setBatchBusy(false);
  }, [batch, batchBusy]);'''
one("  }, [ip, source]);\n\n  const hasInsecureCandidate", "  }, [ip, source]);" + methods + "\n\n  const hasInsecureCandidate", "batch actions")
one(
'''  const hasInsecureCandidate = Boolean(result?.candidates.some((candidate) => candidate.confidence !== "verified"));''',
'''  const hasInsecureCandidate = Boolean(result?.candidates.some((candidate) => candidate.confidence !== "verified"));
  const batchFinished = batch.filter((item) => item.status === "done" || item.status === "error").length;
  const batchFound = batch.filter((item) => Boolean(item.result?.candidates.length)).length;''',
"batch counters",
)

batch_ui = r'''      <div className="flex flex-wrap items-center gap-2 border-t border-border pt-2">
        <label className="inline-flex h-8 cursor-pointer items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted">
          Загрузить список IP
          <input className="hidden" type="file" accept=".txt,.csv,text/plain,text/csv" onChange={(event) => { void loadBatchFile(event.target.files?.[0]); event.target.value = ""; }} />
        </label>
        <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-foreground hover:bg-muted disabled:opacity-50" disabled={!batch.length || batchBusy} onClick={() => void discoverBatch()}>
          {batchBusy ? `Проверено ${batchFinished}/${batch.length}` : `Проверить список${batch.length ? ` (${batch.length})` : ""}`}
        </button>
        {batch.length ? <button type="button" className="inline-flex h-8 items-center rounded-md border border-border px-3 text-xs text-muted-foreground hover:bg-muted" onClick={() => { setBatch([]); setBatchNote(""); setBatchExpanded(false); }}>Очистить список</button> : null}
        <span className="text-[10px] text-muted-foreground">Разделители: запятая, ; или перенос строки. HTTPS-записи пропускаются.</span>
      </div>
      {batchNote ? <p className="text-[11px] text-muted-foreground">{batchNote}</p> : null}
      {batch.length ? (
        <div className="rounded-md border border-border bg-card/60">
          <button type="button" className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left hover:bg-muted/50" onClick={() => setBatchExpanded((current) => !current)}>
            <span className="font-medium text-foreground">Пакетная проверка · {batchFound} найдено · {batchFinished}/{batch.length} завершено</span>
            <span className="text-muted-foreground">{batchExpanded ? "Свернуть" : "Развернуть"}</span>
          </button>
          {batchExpanded ? (
            <div className="max-h-72 overflow-y-auto border-t border-border p-2"><div className="grid gap-2">
              {batch.map((item) => (
                <div key={item.source} className="grid gap-1 rounded-md border border-border bg-background/60 p-2">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-foreground">{item.source}</span>
                    <span className={item.status === "error" ? "text-destructive" : item.status === "done" ? "text-primary" : "text-muted-foreground"}>{item.status === "pending" ? "ожидает" : item.status === "checking" ? "проверяется…" : item.status === "done" ? "готово" : "ошибка"}</span>
                  </div>
                  {item.error ? <div className="text-destructive">{item.error}</div> : null}
                  {item.result && !item.result.candidates.length ? <div className="text-muted-foreground">{item.result.summary}</div> : null}
                  {item.result?.candidates.map((candidate) => (
                    <div key={candidate.domain} className="flex flex-wrap items-center justify-between gap-2">
                      <span className={candidate.confidence === "verified" ? "font-mono text-primary" : "font-mono text-amber-500"}>{candidate.url}</span>
                      <button type="button" className="inline-flex h-7 items-center rounded-md border border-border px-2 text-[11px] text-foreground hover:bg-muted" onClick={() => onUse(candidate.url)}>Использовать</button>
                    </div>
                  ))}
                </div>
              ))}
            </div></div>
          ) : null}
        </div>
      ) : null}
'''
component = text.index("function JitsiHTTPSDiscovery(")
error_anchor = text.index('      {error ? <p className="text-destructive">{error}</p> : null}', component)
text = text[:error_anchor] + batch_ui + text[error_anchor:]
one("/* OLC_JITSI_FORM_LAYOUT_V1 */", "/* OLC_JITSI_FORM_LAYOUT_V1 */\n/* OLC_JITSI_BATCH_IMPORT_V1 */", "marker")

path.write_text(text)
print(f"[jitsi-batch-import] applied: {path}")
PY
