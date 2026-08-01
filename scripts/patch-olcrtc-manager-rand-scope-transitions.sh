#!/usr/bin/env bash
set -euo pipefail
MAIN_GO="${1:?usage: $0 <main.go> <main.tsx>}"
MAIN_TSX="${2:?usage: $0 <main.go> <main.tsx>}"
python3 - "$MAIN_GO" "$MAIN_TSX" <<'PY'
import pathlib, re, sys
gp,tp=map(pathlib.Path,sys.argv[1:3]);g,t=gp.read_text(),tp.read_text()
def rep(s,o,n,label):
    if n in s:return s
    if o not in s:raise SystemExit(f"[scope-transition] missing {label}")
    return s.replace(o,n,1)
q=chr(96)
if 'crypto_randomization_secret,omitempty' not in g:
    g,n=re.subn(r'(?m)^(\tRandomizationSecret\s+string\s+.*randomization_secret,omitempty.*)$',
                r'\1\n\tCryptoRandomizationSecret string          '+q+'json:"crypto_randomization_secret,omitempty"'+q,g,count=1)
    if n != 1: raise SystemExit('[scope-transition] missing Config secret')
g=rep(g,'\ts.cfg.RandomizationSecret = cfg.RandomizationSecret','\ts.cfg.RandomizationSecret = cfg.RandomizationSecret\n\ts.cfg.CryptoRandomizationSecret = cfg.CryptoRandomizationSecret','Supervisor secret')
helpers='''func olcNewRandomizationSecret() (string, error) {
\tbuf := make([]byte, 32)
\tif _, err := rand.Read(buf); err != nil { return "", err }
\treturn hex.EncodeToString(buf), nil
}
func olcCryptoRandomizationSecret(cfg Config) string {
\tif strings.TrimSpace(cfg.CryptoRandomizationSecret) != "" { return cfg.CryptoRandomizationSecret }
\treturn cfg.RandomizationSecret
}
func olcCryptoRandTypeFor(client Client, cfg Config) int {
\tif olcRandScope(cfg) == "client_id" { return 0 }
\tif globalRandomizationEnabled(cfg) {
\t\tif cfg.GlobalSettings != nil && cfg.GlobalSettings.Subscription != nil && cfg.GlobalSettings.Subscription.RandType == 2 { return 2 }
\t\treturn 1
\t}
\tif client.Randomization != nil && client.Randomization.Enabled {
\t\tif client.Randomization.RandType == 2 { return 2 }
\t\treturn 1
\t}
\treturn 0
}
func olcApplyRandScopeTransition(cfg *Config, ac *olcAccessControl, sc string) (int, int, error) {
\toldScope := olcRandScope(*cfg)
\tif cfg.CryptoRandomizationSecret == "" { cfg.CryptoRandomizationSecret = cfg.RandomizationSecret }
\tif sc == "crypto" && oldScope != "crypto" {
\t\tsecret, err := olcNewRandomizationSecret(); if err != nil { return 0, 0, err }
\t\tcfg.RandomizationSecret = secret
\t\tfor i := range cfg.Clients { if cfg.Clients[i].Randomization != nil { cfg.Clients[i].Randomization.RandomizedID = "" } }
\t}
\tif sc == "client_id" && oldScope != "client_id" {
\t\tsecret, err := olcNewRandomizationSecret(); if err != nil { return 0, 0, err }
\t\tcfg.CryptoRandomizationSecret = secret
\t}
\tcfg.GlobalSettings.Subscription.RandScope = sc
\tif sc != "crypto" {
\t\tfor i := range cfg.Clients {
\t\t\tc := &cfg.Clients[i]
\t\t\tif randTypeFor(*c, *cfg) == 1 {
\t\t\t\tif c.Randomization == nil { c.Randomization = &ClientRandomization{} }
\t\t\t\tif c.Randomization.RandomizedID == "" { c.Randomization.RandomizedID = generateRandomizedID(c.ClientID, cfg.RandomizationSecret) }
\t\t\t}
\t\t}
\t}
\tsubReset, connReset := 0, 0
\tif sc == "crypto" {
\t\tif ac.Mode == "keyrand" { ac.Mode = "monitor"; subReset++ }
\t\tfor _, cc := range ac.Clients { if cc != nil && cc.Mode == "keyrand" { cc.Mode = "monitor"; subReset++ } }
\t}
\tif sc == "client_id" {
\t\tif ac.ConnMode == "keyrand" || ac.EnforceConns { ac.ConnMode = "off"; ac.EnforceConns = false; connReset++ }
\t\tfor _, cc := range ac.Clients { if cc != nil && (cc.ConnMode == "keyrand" || cc.ConnEnforce) { cc.ConnMode = "off"; cc.ConnEnforce = false; connReset++ } }
\t}
\treturn subReset, connReset, nil
}

'''
if 'func olcApplyRandScopeTransition(' not in g:g=rep(g,'// randomizationScopeHandler',helpers+'// randomizationScopeHandler','scope helper')
g=rep(g,'func randTypeFor(client Client, cfg Config) int {\n\tif globalRandomizationEnabled(cfg) {','func randTypeFor(client Client, cfg Config) int {\n\tif olcRandScope(cfg) == "crypto" { return 0 }\n\tif globalRandomizationEnabled(cfg) {','subscription gate')
g=g.replace('Secret:  cfg.RandomizationSecret,','Secret:  olcCryptoRandomizationSecret(cfg),').replace('rc.Secret = cfg.RandomizationSecret','rc.Secret = olcCryptoRandomizationSecret(cfg)')
g=rep(g,'\t\trt := randTypeFor(foundClient, cfg)\n\t\tsecret := cfg.RandomizationSecret','\t\trt := olcCryptoRandTypeFor(foundClient, cfg)\n\t\tsecret := olcCryptoRandomizationSecret(cfg)','instance crypto')
canonical='''func olcCanonicalClientID(requestedID string, cfg Config) string {
\tfor _, client := range cfg.Clients { if client.ClientID == requestedID { return client.ClientID } }
\tif resolved, err := resolveClientID(requestedID, cfg); err == nil { return resolved }
\treturn requestedID
}

'''
if 'func olcCanonicalClientID(' not in g:g=rep(g,'func olcAccessDecision(ac olcAccessControl, clientID, hwid, ip string)',canonical+'func olcAccessDecision(ac olcAccessControl, clientID, hwid, ip string)','canonical helper')
g=rep(g,'\t\tolcIP := remoteHost(r)\n\t\tolcActive, olcAllowedDev, olcDeny, olcMode := olcAccessDecision(olcAC, requestedID, olcHwid, olcIP)','\t\tolcIP := remoteHost(r)\n\t\tolcCanonicalID := olcCanonicalClientID(requestedID, cfg)\n\t\tolcActive, olcAllowedDev, olcDeny, olcMode := olcAccessDecision(olcAC, olcCanonicalID, olcHwid, olcIP)','canonical decision')
g=rep(g,'ClientID: requestedID, Path: r.URL.Path, Allowed: olcPass,','ClientID: olcCanonicalID, Path: r.URL.Path, Allowed: olcPass,','canonical log')
g=rep(g,'\t\tcfg.GlobalSettings.Subscription.RandScope = sc\n\t\tif err := saveConfig(configPath, cfg); err != nil {\n\t\t\thttp.Error(w, err.Error(), http.StatusInternalServerError)\n\t\t\treturn\n\t\t}','\t\toldCfg := cfg\n\t\tac := olcAccessLoad()\n\t\tsubReset, connReset, transitionErr := olcApplyRandScopeTransition(&cfg, &ac, sc)\n\t\tif transitionErr != nil { http.Error(w, transitionErr.Error(), http.StatusInternalServerError); return }\n\t\tif err := saveConfig(configPath, cfg); err != nil { http.Error(w, err.Error(), http.StatusInternalServerError); return }\n\t\tif subReset > 0 || connReset > 0 {\n\t\t\tif err := olcAccessSave(ac); err != nil { _ = saveConfig(configPath, oldCfg); http.Error(w, err.Error(), http.StatusInternalServerError); return }\n\t\t}','scope transaction')
g=rep(g,'writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": sc})','writeJSONStatus(w, http.StatusOK, map[string]any{"rand_scope": sc, "subscription_plus_reset": subReset, "connection_plus_reset": connReset})','scope response')
t=rep(t,'  const [randScopeSel, setRandScopeSel] = useState("both");','  const [randScopeSel, setRandScopeSel] = useState("both");\n  const [randScopeSaving, setRandScopeSaving] = useState(false);\n  const [randScopeMsg, setRandScopeMsg] = useState("");\n  const [randScopePending, setRandScopePending] = useState<null | "crypto" | "client_id">(null);','scope UI state')
t=rep(t,'  const saveRandScope = (s: string) => { setRandScopeSel(s); void fetch("/api/settings/randomization/scope", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rand_scope: s }) }).catch(() => {}); };','''  const saveRandScope = async (s: string) => {
    if (s === randScopeSel || randScopeSaving) return;
    setRandScopeSaving(true); setRandScopeMsg("");
    try {
      const r = await fetch("/api/settings/randomization/scope", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ rand_scope: s }) });
      if (!r.ok) throw new Error((await r.text()) || ("HTTP " + r.status));
      const b: any = await r.json(); setRandScopeSel(b.rand_scope || s);
      window.dispatchEvent(new Event("olc-randomization-saved"));
    } catch (e: any) { setRandScopeMsg(e?.message || "Не удалось сохранить область рандомизации"); }
    finally { setRandScopeSaving(false); }
  };
  const requestRandScope = (s: string) => {
    if (s === randScopeSel || randScopeSaving) return;
    if (s === "crypto" || s === "client_id") {
      setRandScopePending(s);
      return;
    }
    void saveRandScope(s);
  };''','scope save')
t=rep(t,'<button type="button" onClick={() => saveRandScope(val)}','<button type="button" disabled={randScopeSaving} onClick={() => requestRandScope(val)}','scope button')
t=rep(t,'  const toggle = () => { const v = !open; setOpen(v); writeStoredBool("olc-addrand-open-v1", v); };\n  return (\n    <div className="grid gap-2 rounded-md border border-border bg-card/30 p-3">','''  const toggle = () => { const v = !open; setOpen(v); writeStoredBool("olc-addrand-open-v1", v); };
  const pendingTitle = randScopePending === "crypto"
    ? "Переключение на «Только ключи»"
    : "Переключение на «Только client_id»";
  const pendingText = randScopePending === "crypto"
    ? "Старые статические и динамические рандомизированные client_id станут недействительны без восстановления. Режим 🎫 «+» будет постоянно сброшен на «Выкл» глобально и у отдельных клиентов. Крипто-рандомизация останется включена: при режиме 🔌 «Выкл» список разрешённых выключен, оригинальные ключи не принимаются. Используйте рандомизированные ключи, настройте «+»/«Блокировать неизвестных» либо отключите рандомизацию."
    : "Старые статические и динамические рандомизированные криптоключи станут недействительны без восстановления. Режим 🔌 «+» будет постоянно сброшен на «Выкл» глобально и у отдельных клиентов. Рандомизация client_id останется включена: при режиме 🎫 «Выкл» список разрешённых выключен, оригинальный client_id не принимается. Используйте рандомизированный URL, настройте «+»/«Блокировать неизвестных» либо отключите рандомизацию.";
  return (
    <>
    {randScopePending && (
      <div className="fixed inset-0 z-[80] grid place-items-center bg-black/65 p-4" onMouseDown={(e) => { if (e.target === e.currentTarget) setRandScopePending(null); }}>
        <div className="w-full max-w-lg rounded-lg border border-amber-500/40 bg-card p-4 shadow-2xl">
          <div className="text-base font-semibold text-foreground">{pendingTitle}</div>
          <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{pendingText}</p>
          <div className="mt-4 flex justify-end gap-2">
            <button type="button" className="rounded-md border border-border px-3 py-1.5 text-sm hover:bg-muted" onClick={() => setRandScopePending(null)}>Отмена</button>
            <button type="button" className="rounded-md border border-amber-500/60 bg-amber-500/15 px-3 py-1.5 text-sm text-amber-300 hover:bg-amber-500/25" onClick={() => { const next = randScopePending; setRandScopePending(null); if (next) void saveRandScope(next); }}>Переключить</button>
          </div>
        </div>
      </div>
    )}
    <div className="grid gap-2 rounded-md border border-border bg-card/30 p-3">''','scope mini-modal')
t=rep(t,'    </div>\n  );\n}\n\n// ============================================================================\n// Olc-cost-l: Info-модалка отдельного инстанса.','''    </div>
    </>
  );
}

// ============================================================================
// Olc-cost-l: Info-модалка отдельного инстанса.''','scope mini-modal close')
t=rep(t,'            <div className="text-[10px] leading-snug text-muted-foreground">Определяет применение','            {randScopeMsg && <div className="text-[11px] text-red-500">{randScopeMsg}</div>}\n            <div className="text-[10px] leading-snug text-muted-foreground">Определяет применение','scope error')
t=rep(t,'  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);','  const [globalRandomizationEnabled, setGlobalRandomizationEnabled] = useState(false);\n  const [globalRandomizationScope, setGlobalRandomizationScope] = useState("both");','App scope')
t=rep(t,'      const randBody = (await randRes.json()) as { enabled: boolean };\n      setGlobalRandomizationEnabled(randBody.enabled ?? false);','      const randBody = (await randRes.json()) as { enabled: boolean; rand_scope?: string };\n      setGlobalRandomizationEnabled(randBody.enabled ?? false);\n      setGlobalRandomizationScope(randBody.rand_scope === "crypto" || randBody.rand_scope === "client_id" ? randBody.rand_scope : "both");','load scope')
t=rep(t,'  const loadAudit = async () => {','  useEffect(() => {\n    const refreshRandomization = () => { void loadState(); void loadSettings(); };\n    window.addEventListener("olc-randomization-saved", refreshRandomization);\n    return () => window.removeEventListener("olc-randomization-saved", refreshRandomization);\n  }, []);\n\n  const loadAudit = async () => {','scope event')
t=rep(t,'function ClientQrModal({ client, path, globalRandomizationEnabled, globalAccessEnabled, accessConfigured, onClose }: { client: any; path?: string; globalRandomizationEnabled?: boolean; globalAccessEnabled?: boolean; accessConfigured?: boolean; onClose: () => void }) {','function ClientQrModal({ client, path, globalRandomizationEnabled, randomizationScope, globalAccessEnabled, accessConfigured, onClose }: { client: any; path?: string; globalRandomizationEnabled?: boolean; randomizationScope?: string; globalAccessEnabled?: boolean; accessConfigured?: boolean; onClose: () => void }) {','QR prop')
t=rep(t,'  const enabled = !!(rnd.enabled || globalRandomizationEnabled);','  const enabled = randomizationScope !== "crypto" && !!(rnd.enabled || globalRandomizationEnabled);','QR gate')
t=rep(t,'            globalRandomizationEnabled={globalRandomizationEnabled}\n            globalAccessEnabled={globalAccessEnabled}','            globalRandomizationEnabled={globalRandomizationEnabled}\n            randomizationScope={globalRandomizationScope}\n            globalAccessEnabled={globalAccessEnabled}','QR pass')
t=rep(t,'                        {client.randomization?.enabled ? (','                        {globalRandomizationScope !== "crypto" && client.randomization?.enabled ? (','card gate')
t=rep(t,') : globalRandomizationEnabled && client.randomization?.randomized_id ? (',') : globalRandomizationScope !== "crypto" && globalRandomizationEnabled && client.randomization?.randomized_id ? (','global card gate')
gp.write_text(g);tp.write_text(t);print('[scope-transition] updated')
PY
cat > "$(dirname "$MAIN_GO")/olc_rand_scope_transition_test.go" <<'GOTEST'
package main
import "testing"
func TestOlcScopeCryptoResetsSubscriptionPlus(t *testing.T){cfg:=Config{RandomizationSecret:"old",Clients:[]Client{{ClientID:"c",Randomization:&ClientRandomization{Enabled:true,RandType:1,RandomizedID:"old-id"}}},GlobalSettings:&GlobalSettings{Subscription:&SubscriptionSettings{RandScope:"both"}}};ac:=olcAccessControl{Mode:"keyrand",Clients:map[string]*olcClientAccess{"c":{Mode:"keyrand"}}};n,_,e:=olcApplyRandScopeTransition(&cfg,&ac,"crypto");if e!=nil{t.Fatal(e)};if n!=2||ac.Mode!="monitor"||ac.Clients["c"].Mode!="monitor"||randTypeFor(cfg.Clients[0],cfg)!=0||cfg.Clients[0].Randomization.RandomizedID!=""||cfg.RandomizationSecret=="old"||olcCryptoRandomizationSecret(cfg)!="old"{t.Fatalf("bad: %+v %+v",cfg,ac)}}
func TestOlcScopeClientIDResetsConnectionPlus(t *testing.T){cfg:=Config{RandomizationSecret:"sub",Clients:[]Client{{ClientID:"c",Randomization:&ClientRandomization{Enabled:true,RandType:2}}},GlobalSettings:&GlobalSettings{Subscription:&SubscriptionSettings{RandScope:"both"}}};ac:=olcAccessControl{ConnMode:"keyrand",EnforceConns:true,Clients:map[string]*olcClientAccess{"c":{ConnMode:"keyrand",ConnEnforce:true}}};_,n,e:=olcApplyRandScopeTransition(&cfg,&ac,"client_id");if e!=nil{t.Fatal(e)};if n!=2||ac.ConnMode!="off"||ac.EnforceConns||ac.Clients["c"].ConnMode!="off"||ac.Clients["c"].ConnEnforce||olcCryptoRandTypeFor(cfg.Clients[0],cfg)!=0||randTypeFor(cfg.Clients[0],cfg)!=2{t.Fatalf("bad: %+v %+v",cfg,ac)}}
func TestOlcScopeBothDoesNotResurrectPlus(t *testing.T){cfg:=Config{RandomizationSecret:"new",Clients:[]Client{{ClientID:"c",Randomization:&ClientRandomization{Enabled:true,RandType:1}}},GlobalSettings:&GlobalSettings{Subscription:&SubscriptionSettings{RandScope:"crypto"}}};ac:=olcAccessControl{Mode:"monitor",ConnMode:"off",Clients:map[string]*olcClientAccess{"c":{Mode:"monitor",ConnMode:"off"}}};_,_,e:=olcApplyRandScopeTransition(&cfg,&ac,"both");if e!=nil{t.Fatal(e)};if ac.Mode!="monitor"||ac.ConnMode!="off"||ac.Clients["c"].Mode!="monitor"||ac.Clients["c"].ConnMode!="off"||cfg.Clients[0].Randomization.RandomizedID==""{t.Fatalf("bad: %+v %+v",cfg,ac)}}
func TestOlcCanonicalRandomizedClientID(t *testing.T){cfg:=Config{RandomizationSecret:"secret",Clients:[]Client{{ClientID:"c",Randomization:&ClientRandomization{Enabled:true,RandType:1,RandomizedID:"random-c"}}},GlobalSettings:&GlobalSettings{Subscription:&SubscriptionSettings{RandScope:"both"}}};if olcCanonicalClientID("random-c",cfg)!="c"||olcCanonicalClientID("c",cfg)!="c"||olcCanonicalClientID("invalid",cfg)!="invalid"{t.Fatal("canonical mapping failed")}}
GOTEST
echo '[scope-transition] tests installed'
