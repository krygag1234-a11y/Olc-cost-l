#!/usr/bin/env bash
# VPS extras skipped when olcrtc-manager-main.go.patch is not applied: liveness, telemost room URL, PUBLIC_URL, ffmpeg path.
set -euo pipefail
MAIN="${1:-${OLCRTC_MGR_REPO:-/tmp/olcrtc-manager-panel}/cmd/olcrtc-manager/main.go}"
[[ -f "$MAIN" ]] || exit 1

python3 - "$MAIN" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text()

if "type olcrtcLivenessConfig struct" not in t:
    t = t.replace(
        "type olcrtcRuntimeConfig struct {",
        """type olcrtcLivenessConfig struct {
\tInterval string `yaml:"interval,omitempty"`
\tTimeout  string `yaml:"timeout,omitempty"`
\tFailures int    `yaml:"failures,omitempty"`
}

type olcrtcRuntimeConfig struct {
\tLiveness *olcrtcLivenessConfig `yaml:"liveness,omitempty"`""",
        1,
    )
    t = t.replace(
        "\tNet    olcrtcNetConfig    `yaml:\"net\"`\n\tSOCKS  olcrtcSocksConfig",
        "\tNet      olcrtcNetConfig      `yaml:\"net\"`\n\tSOCKS    olcrtcSocksConfig",
        1,
    )

if "func defaultLivenessForTransport(" not in t:
    block = '''
func defaultLivenessForTransport(transport string) *olcrtcLivenessConfig {
\tswitch transport {
\tcase "datachannel":
\t\treturn &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
\tcase "vp8channel", "seichannel", "videochannel":
\t\treturn &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
\tdefault:
\t\treturn &olcrtcLivenessConfig{Interval: "10s", Timeout: "5s", Failures: 3}
\t}
}

func ffmpegPathFromEnv() string {
\tif v := strings.TrimSpace(os.Getenv("OLCRTC_FFMPEG")); v != "" {
\t\treturn v
\t}
\tif p, err := exec.LookPath("ffmpeg"); err == nil {
\t\treturn p
\t}
\treturn ""
}

'''
    t = t.replace("func serverConfig(loc Location)", block + "func serverConfig(loc Location)", 1)

if "Liveness: defaultLivenessForTransport" not in t:
    for old, new in [
        (
            "\t\tData: loc.Data,\n\t}",
            "\t\tLiveness: defaultLivenessForTransport(loc.Transport.Type),\n\t\tData:     loc.Data,\n\t\tFFmpeg:   ffmpegPathFromEnv(),\n\t}",
        ),
        (
            "\t\tData:     loc.Data,\n\t}",
            "\t\tLiveness: defaultLivenessForTransport(loc.Transport.Type),\n\t\tData:     loc.Data,\n\t\tFFmpeg:   ffmpegPathFromEnv(),\n\t}",
        ),
    ]:
        if old in t:
            t = t.replace(old, new, 1)
            break

pub_old = """func subscriptionBaseURL(r *http.Request, subscriptionPath string) string {
\tbase := requestOrigin(r)"""
pub_new = """func subscriptionBaseURL(r *http.Request, subscriptionPath string) string {
\tif pub := strings.TrimSpace(os.Getenv("OLCRTC_PUBLIC_URL")); pub != "" {
\t\tbase := strings.TrimRight(pub, "/")
\t\tif subscriptionPath == "" {
\t\t\treturn base + "/"
\t\t}
\t\treturn base + "/" + strings.Trim(subscriptionPath, "/") + "/"
\t}
\tbase := requestOrigin(r)"""
if "OLCRTC_PUBLIC_URL" not in t and pub_old in t:
    t = t.replace(pub_old, pub_new, 1)

p.write_text(t)
if "defaultLivenessForTransport" not in p.read_text():
    print("patch-manager-vps-extras: incomplete"); raise SystemExit(0)
print("[patch-manager-vps-extras] ok"); raise SystemExit(0)
PY
