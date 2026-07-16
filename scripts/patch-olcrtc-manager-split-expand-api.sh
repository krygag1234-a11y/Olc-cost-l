#!/usr/bin/env bash
# Olc-cost-l backend: split action "expand" — deep авто-расширение субдоменов
# групп discovery (Phase 2E; попутно CDN из cert/crt.sh/brand — Phase 2D).
#   POST /api/settings/split/expand  {force?:bool, target?:string}
#     → olc-split-analyze.sh expand-all [--force] [<target>]
# Idempotent. Target: manager main.go. Run after golden-panel copy.
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-split-expand-api] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()

anchor = '''		applySplitRoutingToInstances("split apply-routing")
		writeJSON(w, map[string]any{"status": "ok", "routing_reloaded": splitRoutingReloadSupported(), "instances_restarted": !splitRoutingReloadSupported()})
	default:'''
addition = '''		applySplitRoutingToInstances("split apply-routing")
		writeJSON(w, map[string]any{"status": "ok", "routing_reloaded": splitRoutingReloadSupported(), "instances_restarted": !splitRoutingReloadSupported()})
	case "expand":
		// Phase 2E: deep-расширение субдоменов существующих групп discovery
		// (resolve+CNAME+cert SAN+crt.sh+brand-siblings+CDN). Кэш-TTL внутри
		// инструмента (olc-split-analyze expand-all). force=true — игнорировать TTL;
		// target — расширить одну группу.
		expandArgs := []string{"expand-all"}
		if v, _ := body["force"].(bool); v {
			expandArgs = append(expandArgs, "--force")
		}
		if tgt, _ := body["target"].(string); strings.TrimSpace(tgt) != "" {
			expandArgs = append(expandArgs, strings.TrimSpace(tgt))
		}
		out, err := runSplitTool(context.Background(), expandArgs, nil, 5*time.Minute)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		componentSettingsAfterSave("zapret", map[string]any{})
		writeJSON(w, map[string]any{"status": "ok", "result": out, "settings": mustComponentSettings("split")})
	default:'''

if 'case "expand":' in t:
    print("[patch-split-expand-api] already present")
elif anchor in t:
    t = t.replace(anchor, addition, 1)
    f.write_text(t)
    print("[patch-split-expand-api] OK: added split 'expand' action")
else:
    print("[patch-split-expand-api] WARN: apply-routing/default anchor not found — skip")
PY
