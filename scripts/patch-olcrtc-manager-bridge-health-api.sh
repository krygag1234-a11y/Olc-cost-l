#!/usr/bin/env bash
# Phase 1 (мосты) — bridge health API.
# The bridge script already tracks per-bridge health in
# /var/lib/olcrtc/tor-bridge-health.tsv (fingerprint / ok_total / fail_total /
# fail_streak / last_ok / last_fail / last_status), but the UI never surfaced it.
# This patch:
#   1. adds bridgeHealthList() — joins the ACTIVE bridges.conf lines with the
#      health TSV by fingerprint, returning a per-bridge alive/checked list;
#   2. includes "health" in the bridges GET payload;
#   3. adds a "probe_now" action to the bridges PUT (runs tor-bridge-pool.sh
#      --monitor: probe + update health, no re-fetch / no re-apply).
# Idempotent. Target: manager main.go. Backend patch (apply to $GO).
set -euo pipefail

MAIN_GO="${1:?usage: $0 <path-to-main.go>}"
[[ -f "$MAIN_GO" ]] || { echo "[patch-bridge-health] ERROR: $MAIN_GO not found"; exit 1; }

python3 - "$MAIN_GO" <<'PY'
import sys, pathlib
f = pathlib.Path(sys.argv[1])
t = f.read_text()
changed = False

def repl(old, new, label, guard=None):
    global t, changed
    if guard is not None and guard in t:
        print(f"[patch-bridge-health] {label}: already applied")
        return
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
        print(f"[patch-bridge-health] {label}: ok")
    else:
        print(f"[patch-bridge-health] WARN {label}: anchor not found")

# --- 1. Add bridgeHealthList() + runBridgeProbe() before bridgePoolStats(). ---
repl(
    'func bridgePoolStats() map[string]any {',
    '''// bridgeHealthList joins the ACTIVE bridges.conf lines with the per-bridge
// health TSV (fingerprint\\tok\\tfail\\tstreak\\tlast_ok\\tlast_fail\\tlast_status).
// Returns one entry per active bridge with a resolved alive/checked verdict.
func bridgeHealthList() []map[string]any {
	out := []map[string]any{}
	confB, err := os.ReadFile("/etc/tor/bridges.conf")
	if err != nil {
		return out
	}
	// index health TSV by fingerprint
	type hrow struct {
		ok, fail, streak     int
		lastOK, lastFail     int64
		lastStatus           string
	}
	health := map[string]hrow{}
	if hb, herr := os.ReadFile("/var/lib/olcrtc/tor-bridge-health.tsv"); herr == nil {
		for _, ln := range strings.Split(string(hb), "\\n") {
			cols := strings.Split(ln, "\\t")
			if len(cols) < 7 || cols[0] == "fingerprint" {
				continue
			}
			atoi := func(s string) int { n, _ := strconv.Atoi(strings.TrimSpace(s)); return n }
			atoi64 := func(s string) int64 { n, _ := strconv.ParseInt(strings.TrimSpace(s), 10, 64); return n }
			health[strings.ToUpper(strings.TrimSpace(cols[0]))] = hrow{
				ok: atoi(cols[1]), fail: atoi(cols[2]), streak: atoi(cols[3]),
				lastOK: atoi64(cols[4]), lastFail: atoi64(cols[5]),
				lastStatus: strings.TrimSpace(cols[6]),
			}
		}
	}
	for _, line := range strings.Split(string(confB), "\\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "Bridge ") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 3 {
			continue
		}
		btype := fields[1]
		var addr, fp string
		switch btype {
		case "obfs4", "webtunnel", "snowflake":
			if len(fields) >= 3 {
				addr = fields[2]
			}
			if len(fields) >= 4 {
				fp = strings.ToUpper(fields[3])
			}
		default:
			// vanilla: Bridge <ip:port> <fp>
			addr = fields[1]
			if len(fields) >= 3 {
				fp = strings.ToUpper(fields[2])
			}
			btype = "vanilla"
		}
		entry := map[string]any{
			"type":        btype,
			"addr":        addr,
			"fingerprint": fp,
		}
		if h, ok := health[fp]; ok {
			entry["ok_total"] = h.ok
			entry["fail_total"] = h.fail
			entry["fail_streak"] = h.streak
			entry["last_ok"] = h.lastOK
			entry["last_fail"] = h.lastFail
			entry["last_status"] = h.lastStatus
			// alive verdict: last status ok-ish and no recent fail streak
			alive := (h.lastStatus == "url_ok" || h.lastStatus == "ok" || h.lastStatus == "bootstrap_ok") && h.streak == 0
			entry["alive"] = alive
			if h.lastOK > h.lastFail {
				entry["checked_at"] = h.lastOK
			} else {
				entry["checked_at"] = h.lastFail
			}
			entry["checked"] = true
		} else {
			entry["alive"] = false
			entry["checked"] = false
		}
		out = append(out, entry)
	}
	return out
}

// runBridgeProbe re-probes the active bridges and updates the health DB without
// re-fetching the pool or rewriting bridges.conf (tor-bridge-pool.sh --monitor).
func runBridgeProbe() {
	writeBridgePoolStatus(map[string]any{
		"status":     "running",
		"stage":      "probe",
		"started_at": time.Now().Format(time.RFC3339),
		"types":      "monitor",
		"log_path":   "/var/log/olcrtc-bridge-pool.log",
	})
	go func() {
		repo := olcRepoRoot()
		script := filepath.Join(repo, "scripts/tor-bridge-pool.sh")
		ctx, cancel := context.WithTimeout(context.Background(), 8*time.Minute)
		defer cancel()
		cmd := exec.CommandContext(ctx, "bash", script, "--monitor")
		cmd.Env = append(os.Environ(),
			"PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin",
			"LOG_FILE=/var/log/olcrtc-bridge-pool.log",
		)
		out, err := cmd.CombinedOutput()
		st := map[string]any{
			"status":      "done",
			"stage":       "done",
			"finished_at": time.Now().Format(time.RFC3339),
			"types":       "monitor",
			"pool_stats":  bridgePoolStats(),
			"log_tail":    tailLogFile("/var/log/olcrtc-bridge-pool.log", 40),
		}
		if err != nil {
			st["status"] = "error"
			st["error"] = strings.TrimSpace(err.Error())
			if len(out) > 0 {
				st["output"] = string(out)
			}
		}
		writeBridgePoolStatus(st)
	}()
}

func bridgePoolStats() map[string]any {''',
    "bridgeHealthList + runBridgeProbe",
    guard='func bridgeHealthList()',
)

# --- 2. Include health in the bridges GET payload. ---
repl(
    '''			"pool_job":        readBridgePoolStatus(),
			"pool_stats":      bridgePoolStats(),
			"profiles":        bp,
			"active_profile":  active,
		}, nil''',
    '''			"pool_job":        readBridgePoolStatus(),
			"pool_stats":      bridgePoolStats(),
			"health":          bridgeHealthList(),
			"profiles":        bp,
			"active_profile":  active,
		}, nil''',
    "health in GET payload",
    guard='"health":          bridgeHealthList(),',
)

# --- 3. Add probe_now action to the bridges PUT handler. ---
repl(
    '''			if action, ok := body["action"].(string); ok && action == "refresh_pool" {''',
    '''			if action, ok := body["action"].(string); ok && action == "probe_now" {
					runBridgeProbe()
					writeJSON(w, map[string]any{"status": "ok", "pool_job": readBridgePoolStatus()})
					return
				}
			if action, ok := body["action"].(string); ok && action == "refresh_pool" {''',
    "probe_now action",
    guard='action == "probe_now"',
)

# --- ensure strconv imported (main.go almost certainly has it, but guard) ---
if '"strconv"' not in t:
    repl('\t"strings"\n', '\t"strconv"\n\t"strings"\n', "import strconv")

if changed:
    f.write_text(t)
print("[patch-bridge-health] ok")
PY
