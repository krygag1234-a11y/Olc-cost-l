#!/usr/bin/env bash
# Analyze and apply Split routing domain/IP hints.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="${OLC_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

exec python3 - "$@" <<'PY'
import argparse
import base64
import datetime as dt
import ipaddress
import json
import os
import re
import socket
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(os.environ.get("OLC_REPO_ROOT", "/opt/Olc-cost-l"))
LIST_DIR = Path("/var/lib/olcrtc/lists")
MANIFEST = LIST_DIR / "panel-carrier-discovered.json"
PANEL_HOSTS = LIST_DIR / "panel-carrier-hosts.txt"
PANEL_CIDRS = LIST_DIR / "panel-carrier-cidrs.txt"
RUNTIME_LOG_HOSTS = LIST_DIR / "panel-runtime-log-hosts.txt"
CUSTOM_DIRECT = LIST_DIR / "custom-direct-domains.txt"
GENERATED_DOMAINS = LIST_DIR / "panel-carrier-generated-domains.txt"
GENERATED_CIDRS = LIST_DIR / "panel-carrier-generated-cidrs.txt"
DIRECT_DOMAINS = Path("/var/lib/olcrtc/ru-direct-domains.txt")
DIRECT_CIDRS = Path("/var/lib/olcrtc/ru-cidrs.txt")
FORCE_TOR = Path("/var/lib/olcrtc/force-tor-domains.txt")
BLOCKED_TOR = Path("/var/lib/olcrtc/ru-blocked-tor-domains.txt")
AUTOGEN_BEGIN = "# OLC_SPLIT_AUTOGEN_BEGIN"
AUTOGEN_END = "# OLC_SPLIT_AUTOGEN_END"

HOST_RE = re.compile(r"(?i)\b(?:https?://)?([a-z0-9а-яё.-]+\.[a-zа-яё]{2,}|(?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:/[^\s\"'<>]*)?")
CIDR_RE = re.compile(r"^\s*(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}\s*$")

COMMON_SECOND_LEVEL = {
    "com.ru", "net.ru", "org.ru", "pp.ru", "msk.ru", "spb.ru",
    "co.uk", "com.ua", "com.tr", "com.br", "com.cn",
}


def now():
    return dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_dirs():
    LIST_DIR.mkdir(parents=True, exist_ok=True)
    DIRECT_DOMAINS.parent.mkdir(parents=True, exist_ok=True)
    DIRECT_CIDRS.parent.mkdir(parents=True, exist_ok=True)


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except FileNotFoundError:
        return ""


def write_text(path, data):
    ensure_dirs()
    path.write_text(data, encoding="utf-8")


def clean_line(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return ""
    return line.split("#", 1)[0].strip()


def ordered_unique(items):
    out, seen = [], set()
    for item in items:
        item = item.strip().lower().rstrip(".")
        if not item or item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def target_value(raw):
    raw = (raw or "").strip().strip("\"'")
    if not raw:
        return ""
    if "://" not in raw and "/" in raw:
        raw = raw.split("/", 1)[0]
    if "://" in raw:
        parsed = urllib.parse.urlparse(raw)
        raw = parsed.hostname or raw
    else:
        raw = raw.split("/", 1)[0].split("?", 1)[0]
        if raw.count(":") == 1 and not raw.startswith("["):
            raw = raw.rsplit(":", 1)[0]
    return raw.strip("[]").strip().lower().rstrip(".")


def is_ip(value):
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def is_cidr(value):
    try:
        ipaddress.ip_network(value, strict=False)
        return "/" in value
    except ValueError:
        return False


def base_domain(host):
    parts = host.split(".")
    if len(parts) <= 2:
        return host
    suffix2 = ".".join(parts[-2:])
    suffix3 = ".".join(parts[-3:])
    if suffix2 in COMMON_SECOND_LEVEL and len(parts) >= 3:
        return suffix3
    return suffix2


def domain_candidates(host):
    host = target_value(host)
    if not host or is_ip(host) or is_cidr(host):
        return []
    out = [host, base_domain(host)]
    # olcrtc exact rules already match sub.host via suffix check, but keeping both
    # makes the UI obvious for non-technical users.
    parts = host.split(".")
    for i in range(1, max(1, len(parts) - 1)):
        parent = ".".join(parts[i:])
        if "." in parent:
            out.append(parent)
    return ordered_unique(out)


def read_rules(path):
    rules = []
    for line in read_text(path).splitlines():
        line = clean_line(line)
        if not line:
            continue
        line = line.removeprefix("domain:").removeprefix("full:").removeprefix("regexp:")
        line = line.removeprefix("suffix:").removeprefix("exact:")
        line = line.lstrip("*.").strip().lower().rstrip(".")
        if line:
            rules.append(line)
    return ordered_unique(rules)


def rule_matches(host, rule):
    host = host.lower().rstrip(".")
    rule = rule.lower().rstrip(".").lstrip("*.")
    return host == rule or host.endswith("." + rule)


def classify(host):
    if not host or is_ip(host) or is_cidr(host):
        return {"route": "direct-ip", "matches": []}
    files = [
        ("force_tor", FORCE_TOR, "tor"),
        ("blocked_ru_direct", BLOCKED_TOR, "direct-zapret"),
        ("direct", DIRECT_DOMAINS, "direct"),
        ("seed", ROOT / "data/panel-carrier-domain-seed.txt", "direct"),
        ("vk_seed", ROOT / "data/zapret-vk-cdn-extra.txt", "direct"),
    ]
    matches = []
    for name, path, route in files:
        for rule in read_rules(path):
            if rule_matches(host, rule):
                matches.append({"list": name, "rule": rule, "route": route})
                break
    if host.endswith((".ru", ".su", ".рф")):
        matches.append({"list": "builtin_ru", "rule": "*.ru/*.su/*.рф", "route": "direct"})
    route = matches[0]["route"] if matches else "default-tor"
    return {"route": route, "matches": matches}


def run_cmd(args, timeout=4, input_data=None):
    try:
        p = subprocess.run(args, input=input_data, text=True, capture_output=True, timeout=timeout, check=False)
        if p.returncode == 0:
            return p.stdout.strip()
    except Exception:
        return ""
    return ""


def resolve_host(host):
    ips = []
    try:
        for item in socket.getaddrinfo(host, None):
            addr = item[4][0]
            if addr and addr not in ips:
                ips.append(addr)
    except Exception:
        pass
    cname = ""
    dig = run_cmd(["dig", "+short", "CNAME", host], timeout=3)
    if dig:
        cname = dig.splitlines()[0].rstrip(".")
    return ips[:20], cname


def cert_names(host):
    if is_ip(host) or not host:
        return []
    out = run_cmd(["openssl", "s_client", "-servername", host, "-connect", f"{host}:443", "-showcerts"], timeout=5, input_data="")
    if not out:
        return []
    pem = []
    capture = False
    for line in out.splitlines():
        if "BEGIN CERTIFICATE" in line:
            capture = True
        if capture:
            pem.append(line)
        if "END CERTIFICATE" in line and capture:
            break
    if not pem:
        return []
    text = run_cmd(["openssl", "x509", "-noout", "-text"], timeout=3, input_data="\n".join(pem) + "\n")
    names = []
    for m in re.findall(r"DNS:([^,\s]+)", text):
        names.append(m.lower().lstrip("*.").rstrip("."))
    return ordered_unique(names)[:40]


def crtsh_names(host):
    base = base_domain(host)
    if not base or is_ip(base):
        return []
    url = "https://crt.sh/?q=%25." + urllib.parse.quote(base) + "&output=json"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.loads(r.read().decode("utf-8", "ignore"))
        names = []
        for row in data[:80]:
            for name in str(row.get("name_value", "")).splitlines():
                name = name.strip().lower().lstrip("*.").rstrip(".")
                if name and name.endswith(base):
                    names.append(name)
        return ordered_unique(names)[:80]
    except Exception:
        return []


def whois_summary(value):
    out = run_cmd(["whois", value], timeout=5)
    if not out:
        return ""
    keep = []
    for line in out.splitlines():
        low = line.lower()
        if any(k in low for k in ["orgname", "origin", "originas", "netname", "descr", "country", "registrar"]):
            keep.append(line.strip())
        if len(keep) >= 12:
            break
    return "\n".join(keep)


def analyze(raw, deep=True):
    value = target_value(raw)
    domains, cidrs, ips = [], [], []
    if not value:
        return {"input": raw, "normalized": "", "error": "empty target"}
    if is_cidr(value):
        cidrs = [str(ipaddress.ip_network(value, strict=False))]
    elif is_ip(value):
        ips = [value]
        cidrs = [value + ("/32" if ":" not in value else "/128")]
    else:
        domains = domain_candidates(value)
        resolved, cname = resolve_host(value)
        ips.extend(resolved)
        if cname:
            domains.extend(domain_candidates(cname))
        domains.extend(related_runtime_log_hosts([value]))
        if deep:
            domains.extend(cert_names(value))
            domains.extend(crtsh_names(value))
    ip_cidrs = []
    for ip in ips:
        try:
            ip_cidrs.append(ip + ("/32" if ":" not in ip else "/128"))
        except Exception:
            pass
    domains = ordered_unique(domains)
    cidrs = ordered_unique(cidrs + ip_cidrs)
    classifications = {d: classify(d) for d in domains[:120]}
    return {
        "input": raw,
        "normalized": value,
        "base_domain": base_domain(value) if value and not is_ip(value) and not is_cidr(value) else value,
        "domains": domains[:120],
        "ips": ordered_unique(ips)[:40],
        "cidrs": cidrs[:40],
        "classifications": classifications,
        "whois": whois_summary(value) if deep else "",
        "recommendation": "direct" if not classifications or any(v["route"].startswith("direct") for v in classifications.values()) else "review",
        "generated_at": now(),
    }


def load_manifest():
    try:
        data = json.loads(read_text(MANIFEST) or "{}")
        if not isinstance(data, dict):
            data = {}
    except Exception:
        data = {}
    data.setdefault("schema", 1)
    data.setdefault("updated_at", now())
    data.setdefault("groups", [])
    return data


def save_manifest(data):
    data["updated_at"] = now()
    ensure_dirs()
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def group_id(source, target):
    raw = f"{source}:{target}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")[:48]


def upsert_group(data, source, target, domains, cidrs, label=None, replace_source=False):
    target = target_value(target)
    if source == "analyzer":
        inst = next(
            (g for g in data.get("groups", [])
             if g.get("source") == "instance" and target_value(g.get("target")) == target),
            None,
        )
        if inst:
            source = "instance"
            domains = ordered_unique((inst.get("domains") or []) + list(domains or []))
            cidrs = ordered_unique((inst.get("cidrs") or []) + list(cidrs or []))
    gid = group_id(source, target)
    groups = []
    for g in data.get("groups", []):
        if replace_source and g.get("source") == source:
            continue
        if g.get("id") == gid:
            continue
        if source == "instance" and g.get("source") == "analyzer" and target_value(g.get("target")) == target:
            continue
        groups.append(g)
    existing = next((g for g in data.get("groups", []) if g.get("id") == gid), {})
    selected_domains = ordered_unique(existing.get("selected_domains") or domains)
    selected_cidrs = ordered_unique(existing.get("selected_cidrs") or cidrs)
    groups.append({
        "id": gid,
        "source": source,
        "target": target,
        "label": label or target,
        "domains": ordered_unique(domains),
        "cidrs": ordered_unique(cidrs),
        "selected_domains": selected_domains,
        "selected_cidrs": selected_cidrs,
        "created_at": existing.get("created_at") or now(),
        "updated_at": now(),
    })
    data["groups"] = sorted(groups, key=lambda x: (x.get("source", ""), x.get("label", "")))


def seeded_direct_domains():
    domains = []
    for path in [
        ROOT / "data/zapret-vk-cdn-extra.txt",
        ROOT / "data/panel-carrier-domain-seed.txt",
    ]:
        for line in read_text(path).splitlines():
            line = clean_line(line)
            if not line:
                continue
            if line.startswith("suffix:"):
                line = line[7:].strip().lstrip("*.")
            elif line.startswith("exact:"):
                line = line[6:].strip()
            line = line.lstrip("*.").strip()
            if line:
                domains.extend(domain_candidates(line))
    return ordered_unique(domains)


def is_service_cdn_host(host):
    host = target_value(host)
    if not host or is_ip(host) or is_cidr(host):
        return False
    suffixes = (
        ".vk.com", ".vk.ru", ".vk.cc", ".vk.me", ".vk.link", ".vk-portal.net", ".vk-portal.ru",
        ".userapi.com", ".vkuseraudio.net", ".vkuservideo.net", ".vkuser.net", ".vk-cdn.net",
        ".mail.ru", ".mycdn.me", ".habr.com", ".yandex.ru", ".yandex.net",
    )
    for suffix in suffixes:
        if host == suffix.lstrip(".") or host.endswith(suffix):
            return True
    return False


def service_log_hosts():
    out = []
    for line in read_text(RUNTIME_LOG_HOSTS).splitlines():
        value = target_value(clean_line(line))
        if not value or not is_service_cdn_host(value):
            continue
        out.extend(domain_candidates(value))
    return ordered_unique(out)


def strip_autogen(text):
    lines = text.splitlines()
    out = []
    skipping = False
    for line in lines:
        if line.strip() == AUTOGEN_BEGIN:
            skipping = True
            continue
        if line.strip() == AUTOGEN_END:
            skipping = False
            continue
        if not skipping:
            out.append(line)
    return "\n".join(out).rstrip() + ("\n" if out else "")


def normalize_manual_files():
    domains, cidrs = [], []
    for path in [CUSTOM_DIRECT, PANEL_HOSTS]:
        for line in read_text(path).splitlines():
            line = clean_line(line)
            if not line:
                continue
            value = target_value(line.lstrip("*."))
            if is_cidr(value):
                cidrs.append(str(ipaddress.ip_network(value, strict=False)))
            elif is_ip(value):
                cidrs.append(value + ("/32" if ":" not in value else "/128"))
            else:
                domains.extend(domain_candidates(value))
    for line in read_text(PANEL_CIDRS).splitlines():
        line = clean_line(line)
        if is_cidr(line):
            cidrs.append(str(ipaddress.ip_network(line, strict=False)))
    return ordered_unique(domains), ordered_unique(cidrs)


def rebuild():
    ensure_dirs()
    data = load_manifest()
    domains, cidrs = normalize_manual_files()
    domains.extend(seeded_direct_domains())
    for g in data.get("groups", []):
        domains.extend(g.get("selected_domains") or g.get("domains") or [])
        cidrs.extend(g.get("selected_cidrs") or g.get("cidrs") or [])
    domains = ordered_unique([d.lstrip("*.") for d in domains if d])
    cidrs = ordered_unique(cidrs)
    write_text(GENERATED_DOMAINS, "\n".join(domains) + ("\n" if domains else ""))
    write_text(GENERATED_CIDRS, "\n".join(cidrs) + ("\n" if cidrs else ""))
    domain_block = "\n".join([AUTOGEN_BEGIN, "# generated from panel split settings and discovery", *domains, AUTOGEN_END, ""])
    cidr_block = "\n".join([AUTOGEN_BEGIN, "# generated from panel split settings and discovery", *cidrs, AUTOGEN_END, ""])
    write_text(DIRECT_DOMAINS, strip_autogen(read_text(DIRECT_DOMAINS)).rstrip() + "\n" + domain_block)
    write_text(DIRECT_CIDRS, strip_autogen(read_text(DIRECT_CIDRS)).rstrip() + "\n" + cidr_block)
    return {"status": "ok", "domains": len(domains), "cidrs": len(cidrs), "manifest": str(MANIFEST)}


CARRIER_DEFAULT_HOSTS = {
    "telemost": ["telemost.yandex.ru", "cloud-api.yandex.ru", "yandex.ru"],
    "wbstream": ["stream.wb.ru", "wb.ru"],
    "jazz": [],
    "jitsi": [],
}


def carrier_seed_hosts():
    out = []
    for hosts in CARRIER_DEFAULT_HOSTS.values():
        out.extend(hosts)
    for line in read_text(ROOT / "data/zapret-carrier-hosts.txt").splitlines():
        line = clean_line(line)
        if not line or line.startswith("suffix:"):
            continue
        out.append(line.lstrip("*."))
    return ordered_unique(out)


def location_targets(loc):
    if not isinstance(loc, dict):
        return []
    targets = []
    carrier = (loc.get("carrier") or "").strip().lower()
    endpoint = loc.get("endpoint") if isinstance(loc.get("endpoint"), dict) else {}
    room = target_value(endpoint.get("room_id") or loc.get("room_id") or "")
    dns_raw = (loc.get("dns") or "").strip()
    if dns_raw:
        dns_host = target_value(dns_raw.split(",")[0].split()[0])
        if dns_host:
            targets.append(dns_host)
    if room:
        if is_ip(room) or is_cidr(room) or "." in room:
            targets.append(room)
    for host in CARRIER_DEFAULT_HOSTS.get(carrier, []):
        targets.append(host)
    transport = loc.get("transport") if isinstance(loc.get("transport"), dict) else {}
    payload = transport.get("payload") if isinstance(transport.get("payload"), dict) else loc.get("payload")
    if isinstance(payload, dict):
        for value in payload.values():
            if isinstance(value, str):
                for match in HOST_RE.finditer(value):
                    targets.append(match.group(1))
    return ordered_unique([target_value(t) for t in targets if target_value(t)])


def extract_config_targets(cfg):
    targets = []
    if not isinstance(cfg, dict):
        return targets
    for client in cfg.get("clients") or []:
        if not isinstance(client, dict):
            continue
        for loc in client.get("locations") or []:
            targets.extend(location_targets(loc))
    return ordered_unique(targets)


def extract_targets(obj):
    if isinstance(obj, dict) and "clients" in obj:
        return extract_config_targets(obj)
    targets = []
    def walk(v, key=""):
        if isinstance(v, dict):
            for kk, vv in v.items():
                walk(vv, kk)
        elif isinstance(v, list):
            for vv in v:
                walk(vv, key)
        elif isinstance(v, str):
            s = v.strip()
            if not s:
                return
            if key in {"room_id", "link", "dns", "url", "host", "server", "endpoint"} or HOST_RE.search(s):
                for m in HOST_RE.finditer(s):
                    targets.append(m.group(1))
                if "." in s and " " not in s:
                    targets.append(s)
    walk(obj)
    return ordered_unique([target_value(t) for t in targets if target_value(t)])


def host_related(host, anchors):
    host = target_value(host)
    if not host or is_ip(host) or is_cidr(host):
        return False
    host_base = base_domain(host)
    for anchor in anchors:
        anchor = target_value(anchor)
        if not anchor or is_ip(anchor) or is_cidr(anchor):
            continue
        anchor_base = base_domain(anchor)
        if host == anchor or host.endswith("." + anchor) or anchor.endswith("." + host):
            return True
        if host_base == anchor_base:
            return True
    return False


def related_runtime_log_hosts(anchors):
    if not anchors:
        return []
    out = []
    for line in read_text(RUNTIME_LOG_HOSTS).splitlines():
        value = target_value(clean_line(line))
        if host_related(value, anchors):
            out.extend(domain_candidates(value))
    return ordered_unique(out)


def sync_config(path):
    data = load_manifest()
    data["groups"] = [g for g in data.get("groups", []) if g.get("source") != "instance"]
    try:
        cfg = json.loads(read_text(Path(path)))
    except Exception as e:
        raise SystemExit(f"cannot read config: {e}")
    instance_targets = extract_config_targets(cfg)
    if not instance_targets:
        instance_targets = extract_targets(cfg)
    anchors = ordered_unique(instance_targets + read_rules(CUSTOM_DIRECT) + read_rules(PANEL_HOSTS) + seeded_direct_domains())
    log_hosts = ordered_unique(related_runtime_log_hosts(anchors) + service_log_hosts())
    visible_hosts, visible_cidrs = list(log_hosts), []
    for target in instance_targets[:20]:
        res = analyze(target, deep=False)
        visible_hosts.extend(res.get("domains", []))
        visible_cidrs.extend(res.get("cidrs", []))
        upsert_group(data, "instance", target, res.get("domains", []), res.get("cidrs", []), label=target)
    for host in log_hosts:
        domains = domain_candidates(host)
        upsert_group(data, "instance", host, domains, [], label=host)
        visible_hosts.extend(domains)
    visible_hosts = ordered_unique(visible_hosts + instance_targets + log_hosts)
    write_text(PANEL_HOSTS, "\n".join(visible_hosts) + ("\n" if visible_hosts else ""))
    write_text(PANEL_CIDRS, "\n".join(ordered_unique(visible_cidrs)) + ("\n" if visible_cidrs else ""))
    if log_hosts:
        cur = read_rules(CUSTOM_DIRECT)
        write_text(CUSTOM_DIRECT, "\n".join(ordered_unique(cur + log_hosts)) + ("\n" if cur or log_hosts else ""))
    save_manifest(data)
    rebuilt = rebuild()
    return {
        "status": "ok",
        "targets": len(instance_targets),
        "hosts": len(visible_hosts),
        "cidrs": len(visible_cidrs),
        "log_hosts": len(log_hosts),
        **rebuilt,
    }


def sync_logs():
    anchors = read_rules(CUSTOM_DIRECT) + read_rules(PANEL_HOSTS) + seeded_direct_domains()
    try:
        cfg = json.loads(read_text(Path("/etc/olcrtc-manager/config.json")))
        anchors.extend(extract_config_targets(cfg))
    except Exception:
        pass
    anchors = ordered_unique([target_value(a) for a in anchors if target_value(a)])
    hosts = ordered_unique(related_runtime_log_hosts(anchors) + service_log_hosts())
    cur = read_rules(CUSTOM_DIRECT)
    if not hosts:
        out = rebuild()
        out["added"] = 0
        return out
    merged = ordered_unique(cur + hosts)
    write_text(CUSTOM_DIRECT, "\n".join(merged) + ("\n" if merged else ""))
    out = rebuild()
    out["added"] = max(0, len(merged) - len(cur))
    out["hosts"] = len(hosts)
    return out


def apply_analysis(payload):
    data = load_manifest()
    target = target_value(payload.get("target") or payload.get("normalized") or payload.get("input") or "")
    domains = payload.get("selected_domains") or payload.get("domains") or []
    cidrs = payload.get("selected_cidrs") or payload.get("cidrs") or []
    target_list = (payload.get("target_list") or payload.get("mode") or "direct").strip().lower()
    if not target:
        raise SystemExit("target is required")
    if target_list in {"force_tor", "tor"}:
        existing = read_rules(FORCE_TOR)
        write_text(FORCE_TOR, "\n".join(ordered_unique(existing + domains)) + "\n")
        return {"status": "ok", "target_list": "force_tor", "domains": len(domains), "cidrs": 0}
    if target_list in {"blocked_tor", "blocked_ru", "zapret"}:
        existing = read_rules(BLOCKED_TOR)
        write_text(BLOCKED_TOR, "\n".join(ordered_unique(existing + domains)) + "\n")
        return {"status": "ok", "target_list": "blocked_tor", "domains": len(domains), "cidrs": 0}
    if target_list in {"manual", "custom_direct"}:
        cur = read_rules(CUSTOM_DIRECT)
        manual_domains = ordered_unique(cur + [d for d in domains if d and not is_cidr(d)])
        manual_cidrs = ordered_unique([c for c in cidrs if is_cidr(c)])
        for d in domains:
            if is_ip(d):
                manual_cidrs.append(d + ("/32" if ":" not in d else "/128"))
        write_text(CUSTOM_DIRECT, "\n".join(manual_domains + manual_cidrs) + ("\n" if manual_domains or manual_cidrs else ""))
        if manual_cidrs:
            cur_c = [clean_line(x) for x in read_text(PANEL_CIDRS).splitlines() if clean_line(x)]
            write_text(PANEL_CIDRS, "\n".join(ordered_unique(cur_c + manual_cidrs)) + "\n")
        out = rebuild()
        out["target_list"] = "custom_direct"
        return out
    upsert_group(data, payload.get("source", "analyzer"), target, domains, cidrs, label=payload.get("label") or target)
    save_manifest(data)
    out = rebuild()
    out["target_list"] = "direct"
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["analyze", "sync-config", "sync-logs", "rebuild", "apply-analysis", "manifest"])
    p.add_argument("target", nargs="?")
    p.add_argument("--config", default="/etc/olcrtc-manager/config.json")
    p.add_argument("--shallow", action="store_true")
    args = p.parse_args()
    if args.command == "analyze":
        print(json.dumps(analyze(args.target or "", deep=not args.shallow), ensure_ascii=False, indent=2))
    elif args.command == "sync-config":
        print(json.dumps(sync_config(args.target or args.config), ensure_ascii=False, indent=2))
    elif args.command == "sync-logs":
        print(json.dumps(sync_logs(), ensure_ascii=False, indent=2))
    elif args.command == "rebuild":
        print(json.dumps(rebuild(), ensure_ascii=False, indent=2))
    elif args.command == "apply-analysis":
        raw_payload = os.environ.get("OLC_SPLIT_TOOL_INPUT", "").strip()
        payload = json.loads(raw_payload) if raw_payload else json.load(sys.stdin)
        print(json.dumps(apply_analysis(payload), ensure_ascii=False, indent=2))
    elif args.command == "manifest":
        print(json.dumps(load_manifest(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
PY
