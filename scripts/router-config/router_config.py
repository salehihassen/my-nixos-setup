#!/usr/bin/env python3
"""On-demand GL.iNet configuration backup, comparison and guarded repair."""

import argparse
import datetime as dt
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import uuid


CONFIG = Path.home() / ".config/router-config/site.json"
STATE = Path.home() / ".local/state/router-config"
PACKAGES = ("network", "wireless", "dhcp", "firewall", "glconfig", "repeater", "system")
IDENTIFIER = re.compile(r"^[A-Za-z0-9_]+$")
SECTION = re.compile(r"^(?:[A-Za-z0-9_]+|@[A-Za-z0-9_]+\[[0-9]+\])$")

RECONNECT_WDS = r'''lua - <<'RECONNECT_WDS'
local c = require('uci').cursor()
if c:get('glconfig', 'general', 'mode') == 'wds' and c:get('repeater', '@main[0]', 'disabled') == '0' then
    local con = assert(require('ubus').connect())
    local status = con:call('repeater', 'status', {})
    if not status or status.state_s ~= 'connected' then
        local selected
        c:foreach('repeater', 'network', function(n)
            if n.selected == '1' then selected = n end
        end)
        assert(selected and selected.ssid and selected.key, 'Saved WDS connection unavailable')
        con:call('repeater', 'connect', {ssid=selected.ssid, key=selected.key,
            wds=true, remember=true, network='lan', protocol='dhcp'})
    end
    con:close()
end
RECONNECT_WDS'''


class Error(Exception):
    pass


def run(argv, data=None, timeout=30):
    env = dict(os.environ, SSH_ASKPASS_REQUIRE="never")
    env.pop("DISPLAY", None)
    try:
        p = subprocess.run(argv, input=data, capture_output=True, timeout=timeout, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Error(f"{Path(argv[0]).name} failed ({type(exc).__name__})") from None
    if p.returncode:
        # Never echo a remote command, configuration value, or raw tool error.
        raise Error(f"{Path(argv[0]).name} failed (exit {p.returncode}); check connectivity and an unlocked SSH agent")
    return p.stdout


def ssh(site, target, command, data=None, timeout=30):
    sock = os.environ.get("SSH_AUTH_SOCK", "")
    if not sock or "/gcr/" in sock or "/keyring/" in sock:
        raise Error("Use an already-unlocked ordinary SSH agent; desktop keyring prompts are disabled")
    run(["ssh-add", "-l"], timeout=5)
    # No implicit keyring fallback, password login, host-key enrollment, or prompt.
    args = ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
            "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2", "-o", f"IdentityAgent={sock}",
            "-o", "IdentitiesOnly=yes", "-i", os.path.expanduser(site["identity_file"])]
    if target.get("host_key_alias"):
        args += ["-o", "HostKeyAlias=" + target["host_key_alias"]]
    return run(args + [target["ssh"], command], data, timeout)


def private_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
        tmp = Path(out.name)
        os.chmod(tmp, 0o600)
        out.write((json.dumps(value, indent=2) + "\n").encode())
    os.replace(tmp, path)


def load_site(path):
    site = json.loads(Path(path).read_text())
    if site.get("schema") != 1 or not site.get("routers"):
        raise Error("Expected a schema-1 site file with routers")
    for name, router in site["routers"].items():
        if not IDENTIFIER.fullmatch(name):
            raise Error("Invalid router name")
        if not re.fullmatch(r"[A-Za-z0-9_.@:-]+", router["ssh"]) or router["ssh"].startswith("-"):
            raise Error("Invalid SSH destination")
        nets = [ipaddress.ip_network(n, strict=False) for n in router.get("subnets", {}).values()]
        if any(a.overlaps(b) for i, a in enumerate(nets) for b in nets[i + 1:]):
            raise Error(f"{name}: intended subnets overlap")
    backup = site["backup"]
    if not re.fullmatch(r"[A-Za-z0-9_.@:-]+", backup["ssh"]) or backup["ssh"].startswith("-"):
        raise Error("Invalid NAS destination")
    if not Path(backup["directory"]).is_absolute() or ".." in Path(backup["directory"]).parts:
        raise Error("Backup directory must be an absolute path")
    return site


# UCI's Lua API returns section types, stable names and anonymous indices without
# interpreting UCI export text as shell code. Secret values stay in memory.
INSPECT = r'''
local uci = require('uci').cursor()
local json = require('cjson')
local bus = assert(require('ubus').connect())
local result = { board = bus:call('system', 'board', {}), configs = {} }
local f = io.open('/etc/glversion', 'r')
result.firmware = f and f:read('*l') or ''
if f then f:close() end
for _, package in ipairs(uci:configs()) do
    local sections = {}
    local counts = {}
    uci:foreach(package, nil, function(s)
        local kind = s['.type']
        local index = counts[kind] or 0
        counts[kind] = index + 1
        local name = s['.anonymous'] and ('@' .. kind .. '[' .. index .. ']') or s['.name']
        local opts = {}
        for k, v in pairs(s) do if k:sub(1,1) ~= '.' then opts[k] = v end end
        sections[#sections+1] = { name = name, type = kind, options = opts }
    end)
    result.configs[package] = sections
end
result.interfaces = bus:call('network.interface', 'dump', {})
-- Avoid returning portal credentials or the repeater's saved network password.
local s = bus:call('repeater', 'status', {})
if s then result.repeater = { state = s.state_s, running = s.running, fail_type = s.fail_type } end
bus:close()
print(json.encode(result))
'''


def inspect(site, router):
    try:
        info = json.loads(ssh(site, router, "lua -", INSPECT.encode()))
    except (ValueError, KeyError):
        raise Error("Router inspection did not return the expected JSON") from None
    model = info.get("board", {}).get("model", "")
    if router["model"].lower() not in model.lower():
        raise Error(f"Model mismatch: expected {router['model']}; refusing this device")
    return info


def select(configs, item):
    sections = configs.get(item["package"], [])
    if "match" in item:
        match = item["match"]
        def matches(s):
            value = s["options"].get(match["option"], "")
            if match["option"] == "mac":
                values = value if isinstance(value, list) else value.split()
                return match["value"].lower() in [v.lower() for v in values]
            return value == match["value"]
        found = [s for s in sections if s["type"] == item["type"] and matches(s)]
    else:
        found = [s for s in sections if s["name"] == item["section"]]
    if len(found) > 1:
        raise Error("Ambiguous section selector; resolve duplicate entries first")
    if found:
        if found[0]["type"] != item["type"]:
            raise Error("Section type changed; review firmware migration before repair")
        return found[0]
    if item.get("create") and "match" in item:
        name = item["create"]
        if any(s["name"] == name for s in sections):
            raise Error("New reservation section name is already occupied")
        return {"name": name, "type": item["type"], "options": {}, "new": True}
    raise Error(f"Required section missing in {item['package']}; review the firmware layout")


def desired(site, name, router):
    path = STATE / (name + ".baseline.json")
    if path.exists():
        if path.stat().st_mode & 0o077:
            raise Error("Baseline contains credentials; restrict its permissions to 600")
        baseline = json.loads(path.read_text())
        if baseline["model"] != router["model"]:
            raise Error("Baseline model does not match this router")
        items = baseline["desired"]
        # Explicit site policy takes precedence without conflicting writes.
        for wanted in router["desired"]:
            configs = {}
            for item in items:
                configs.setdefault(item["package"], []).append({
                    "name": item.get("section", item.get("create", "")),
                    "type": item["type"], "options": item["options"]})
            try:
                selected = select(configs, wanted)
            except Error:
                raise Error("Site policy cannot be matched to the saved baseline; review it before applying") from None
            matched = next((i for i in items if i["package"] == wanted["package"] and
                            i.get("section", i.get("create", "")) == selected["name"]), None)
            if matched is None:
                items.append(wanted)
            else:
                options = dict(matched["options"], **wanted["options"])
                matched.update(wanted)
                matched["options"] = options
        return items, baseline["firmware"]
    return router["desired"], router["firmware"]


def differences(info, items):
    changes = []
    for item in items:
        package = item["package"]
        if package not in PACKAGES:
            raise Error(f"Unsupported repair package: {package}")
        section = select(info["configs"], item)
        for option, value in item["options"].items():
            if not IDENTIFIER.fullmatch(option) or not SECTION.fullmatch(section["name"]):
                raise Error("Invalid UCI identifier")
            if not isinstance(value, (str, list)) or (isinstance(value, list) and not all(isinstance(v, str) for v in value)):
                raise Error("UCI values must be strings or lists of strings")
            before = section["options"].get(option)
            equivalent = before == value
            if option in ("mac", "macaddr", "bssid") and isinstance(before, str) and isinstance(value, str):
                equivalent = before.lower() == value.lower()
            if not equivalent:
                changes.append((package, section, option, before, value))
    return changes


def overlaps(info):
    networks = []
    for interface in info.get("interfaces", {}).get("interface", []):
        if not interface.get("up") or interface.get("interface") == "loopback":
            continue
        for addr in interface.get("ipv4-address", []):
            networks.append((interface["interface"], ipaddress.ip_network(f"{addr['address']}/{addr['mask']}", strict=False)))
    return [(a, b) for i, (a, x) in enumerate(networks) for b, y in networks[i + 1:] if a != b and x.overlaps(y)]


def check_info(router, info, items):
    problems = []
    for a, b in overlaps(info):
        problems.append(f"active subnets overlap: {a} and {b}")
    for name, wanted in router.get("subnets", {}).items():
        matching = [i for i in info.get("interfaces", {}).get("interface", []) if i.get("interface") == name]
        expected = ipaddress.ip_interface(wanted)
        if not any(i.get("up") and any(ipaddress.ip_interface(f"{a['address']}/{a['mask']}") == expected for a in i.get("ipv4-address", [])) for i in matching):
            problems.append(f"{name} runtime address differs from its intended address")
    if router.get("wds") and info.get("repeater", {}).get("state") != "connected":
        problems.append("WDS uplink is not connected")
    reserved = {}
    for section in info["configs"].get("dhcp", []):
        ip = section["options"].get("ip")
        if section["type"] == "host" and ip and ip != "ignore":
            if ip in reserved:
                problems.append("multiple DHCP reservations use the same address")
            reserved[ip] = section["name"]
    for package, section, option, _, _ in differences(info, items):
        problems.append(f"configuration drift: {package}.{section['name']}.{option}")
    return problems


def print_plan(changes):
    for package, section, option, _, _ in changes:
        # Print option paths only. Even SSIDs, addresses and DNS names stay private.
        print(f"  SET {package}.{section['name']}.{option} (value hidden)")
    if not changes:
        print("  No managed settings differ")


def shell_value(key, value):
    return "uci set " + shlex.quote(key + "=" + value)


def repair_script(changes, token):
    packages = sorted({c[0] for c in changes})
    for package, section, option, _, _ in changes:
        if not IDENTIFIER.fullmatch(package) or not SECTION.fullmatch(section["name"]) or not IDENTIFIER.fullmatch(option):
            raise Error("Invalid UCI repair path")
        if package == "glconfig" and section["name"] == "general" and option == "mode":
            raise Error("Changing network mode requires GL.iNet's mode migration; use its admin page")
    directory = "/tmp/router-config-" + token
    reloads = []
    if "network" in packages:
        reloads.append("/etc/init.d/network reload")
    if "wireless" in packages:
        reloads.append("wifi reload")
    if "dhcp" in packages:
        reloads.append("/etc/init.d/dnsmasq restart")
    if "firewall" in packages:
        reloads.append("/etc/init.d/firewall reload")
    if "repeater" in packages:
        reloads.append("ubus call repeater reload '{}' >/dev/null")
        reloads.append(RECONNECT_WDS)
    if "system" in packages:
        reloads.append("/etc/init.d/system reload")
    reload = "\n".join(reloads) or ":"
    # A detached, finite timer restores only the touched files if the client
    # cannot verify access after applying. It doesn't depend on a live SSH pipe.
    undo = ["#!/bin/sh", "sleep 120", f"if ! test -f {directory}/confirmed; then"]
    # Discard any staged delta left by a failed set/commit before restoring.
    undo += [f"uci -q revert {p} || true\ncp -p {directory}/{p} /etc/config/{p}" for p in packages]
    undo += [reload, "fi", f"for file in {directory}/*; do unlink \"$file\"; done",
             f"rmdir {directory}", "rmdir /tmp/router-config-apply.lock"]
    lines = ["set -eu", "umask 077", "mkdir /tmp/router-config-apply.lock",
             f"trap 'rm -rf {directory}; rmdir /tmp/router-config-apply.lock' EXIT",
             f"mkdir {directory}"]
    lines += [f"test -z \"$(uci changes {p})\" || exit 20" for p in packages]
    lines += [f"cp -p /etc/config/{p} {directory}/{p}" for p in packages]
    lines += [f"cat > {directory}/rollback.sh <<'ROLLBACK'", "\n".join(undo), "ROLLBACK",
              f"nohup sh {directory}/rollback.sh >/dev/null 2>&1 </dev/null &",
              "trap - EXIT"]
    created = set()
    for package, section, option, _, value in changes:
        name = section["name"]
        if section.get("new") and (package, name) not in created:
            if not IDENTIFIER.fullmatch(name) or not IDENTIFIER.fullmatch(section["type"]):
                raise Error("Invalid new section")
            lines.append(shell_value(package + "." + name, section["type"]))
            created.add((package, name))
        key = f"{package}.{name}.{option}"
        if isinstance(value, list):
            lines.append("uci -q delete " + shlex.quote(key) + " || true")
            lines += ["uci add_list " + shlex.quote(key + "=" + v) for v in value]
        else:
            lines.append(shell_value(key, value))
    lines += ["uci commit " + p for p in packages]
    lines += [f"cat > {directory}/reload.sh <<'RELOAD'", "sleep 2\n" + reload, "RELOAD",
              f"nohup sh {directory}/reload.sh >/dev/null 2>&1 </dev/null &"]
    return "\n".join(lines).encode() + b"\n"


def validate_archive(raw):
    try:
        with tarfile.open(fileobj=io.BytesIO(raw), mode="r:gz") as archive:
            names = archive.getnames()
            if not names or not any(n.lstrip("./").startswith("etc/config/") for n in names):
                raise Error("Native archive lacks router configuration files")
            for member in archive.getmembers():
                if member.name.startswith("/") or ".." in Path(member.name).parts:
                    raise Error("Unsafe archive member")
    except (tarfile.TarError, EOFError):
        raise Error("Router returned an invalid native backup") from None


def make_bundle(name, router, info, native, packages, file_list):
    validate_archive(native)
    metadata = {"schema": 1, "router": name, "model": router["model"],
                "firmware": info["firmware"], "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "native_sha256": hashlib.sha256(native).hexdigest()}
    files = {"metadata.json": json.dumps(metadata, indent=2).encode(),
             "native-backup.tar.gz": native, "inspection.json": json.dumps(info).encode(),
             "installed-packages.txt": packages, "backup-file-list.txt": file_list}
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as archive:
        for filename, contents in files.items():
            member = tarfile.TarInfo(filename)
            member.mode = 0o600
            member.size = len(contents)
            archive.addfile(member, io.BytesIO(contents))
    return out.getvalue()


def nas_preflight(site):
    target = site["backup"]
    mount = shlex.quote(target["pool_mount"])
    host = shlex.quote(target["expected_hostname"])
    script = f'''set -eu
test "$(hostname -s)" = {host}
command -v pgrep >/dev/null
if pgrep -x snapraid >/dev/null; then exit 21; fi
test "$(findmnt -rn -T {mount} -o TARGET)" = {mount}
test -d {mount}/vault
printf 'NAS ready\\n'
'''
    ssh(site, target, "sh -s", script.encode())


def upload(site, filename, encrypted):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+\.tar\.gz\.age", filename):
        raise Error("Invalid archive filename")
    target = site["backup"]
    root = shlex.quote(target["directory"])
    final = shlex.quote(target["directory"] + "/" + filename)
    partial_path = target["directory"] + "/." + filename + ".partial-" + uuid.uuid4().hex
    part = shlex.quote(partial_path)
    cleanup = shlex.quote("unlink -- " + shlex.quote(partial_path))
    checksum = hashlib.sha256(encrypted).hexdigest()
    # No NAS writes until this explicit backup path. Recheck sync before write;
    # stage and verify in the destination directory, then publish atomically.
    command = f'''set -eu
umask 077
if pgrep -x snapraid >/dev/null; then exit 21; fi
test "$(findmnt -rn -T {shlex.quote(target['pool_mount'])} -o TARGET)" = {shlex.quote(target['pool_mount'])}
mkdir -p {root}
chmod 700 {root}
test ! -e {final}
trap {cleanup} EXIT HUP INT TERM
cat > {part}
test "$(sha256sum {part} | cut -d ' ' -f 1)" = {checksum}
ln {part} {final}
printf '%s\\n' {shlex.quote(checksum + '  ' + filename)} > {final}.sha256
'''
    ssh(site, target, command, encrypted, timeout=180)


def capture_baseline(name, router, info):
    items = []
    for package in PACKAGES:
        for section in info["configs"].get(package, []):
            items.append({"package": package, "section": section["name"],
                          "type": section["type"], "options": section["options"]})
    private_json(STATE / (name + ".baseline.json"),
                 {"model": router["model"], "firmware": info["firmware"], "desired": items})


def backup(site, names, accept_baseline=False):
    if not shutil.which("age"):
        raise Error("age is required for encrypted backups; use the Nix launcher")
    public_key = Path(os.path.expanduser(site["recipient_file"]))
    if not public_key.is_file():
        raise Error("Backup encryption recipient file is missing")
    nas_preflight(site)
    # Inspect EVERY selected router and reject known-bad states before creating
    # any archive. A partial run never silently promotes a broken baseline.
    infos = {}
    for name in names:
        router = site["routers"][name]
        info = inspect(site, router)
        expected, _ = desired(site, name, router) if accept_baseline else (router["desired"], None)
        issues = check_info(router, info, expected)
        if issues:
            raise Error(f"{name}: fix health/configuration checks before backup: " + "; ".join(issues))
        infos[name] = info
    for name, info in infos.items():
        router = site["routers"][name]
        file_list = ssh(site, router, "sysupgrade -l", timeout=30)
        native = ssh(site, router, "sysupgrade -b -", timeout=90)
        packages = ssh(site, router, "if command -v opkg >/dev/null; then opkg list-installed; elif command -v apk >/dev/null; then apk info -v; else exit 22; fi")
        after = inspect(site, router)
        if after["configs"] != info["configs"] or after["firmware"] != info["firmware"]:
            raise Error(f"{name}: configuration changed during capture; retry after edits finish")
        encrypted = run(["age", "-R", str(public_key)], make_bundle(name, router, info, native, packages, file_list), timeout=60)
        filename = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + name + "-" + uuid.uuid4().hex[:8] + ".tar.gz.age"
        upload(site, filename, encrypted)
        print(f"{name}: encrypted backup verified on u3: {filename}")
        if accept_baseline:
            capture_baseline(name, router, info)
            print(f"{name}: private local baseline saved (contains credentials; mode 600)")


def network_check(site):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    failures = 0
    for name, router in site["routers"].items():
        try:
            with opener.open(router["admin_url"], timeout=4) as response:
                ok = response.status == 200
        except (OSError, ValueError):
            ok = False
        print(f"{'PASS' if ok else 'FAIL'} {name}: admin HTTP reachable")
        failures += not ok
    for target in site.get("network_checks", []):
        try:
            gateway = str(ipaddress.IPv4Address(target["gateway"]))
            interface = target["interface"]
            if not re.fullmatch(r"[A-Za-z0-9_.:-]+", interface):
                raise Error("Invalid health-check interface")
            script = ("set -eu\n" + "ip -4 route get " + shlex.quote(gateway) + "\n" +
                      "ping -I " + shlex.quote(interface) + " -c 2 -W 2 " + shlex.quote(gateway) + " >/dev/null\n" + '''
timeout 6 getent ahostsv4 us.archive.ubuntu.com >/dev/null
''' + "timeout 8 curl -q --noproxy '*' --interface " + shlex.quote(interface) + ''' -4 -fsS --connect-timeout 3 --max-time 6 -o /dev/null https://archive.ubuntu.com/ubuntu/dists/noble/Release
printf 'gateway, DNS and Ubuntu HTTPS passed\\n'
''')
            ssh(site, target, "sh -s", script.encode(), timeout=25)
            print(f"PASS {target['name']}: gateway, DNS and Ubuntu HTTPS")
        except Error as exc:
            print(f"FAIL {target['name']}: {exc}")
            failures += 1
    try:
        active = run(["nmcli", "-g", "NAME", "connection", "show", "--active"]).decode().splitlines()
        if "office-router-diagnostic" in active:
            print("WARN j2: temporary office-router-diagnostic Ethernet profile is still active")
    except Error:
        pass
    return failures


def apply(site, name, execute):
    router = site["routers"][name]
    items, approved = desired(site, name, router)
    info = inspect(site, router)
    changes = differences(info, items)
    print_plan(changes)
    if not execute or not changes:
        return
    if info["firmware"] != approved:
        raise Error("Firmware differs from the reviewed baseline; review/migrate it before applying")
    token = uuid.uuid4().hex
    ssh(site, router, "sh -s", repair_script(changes, token))
    # One delayed verification, not an unattended reconciliation loop.
    import time
    time.sleep(12)
    after = inspect(site, router)
    issues = check_info(router, after, items)
    if issues:
        raise Error("Repair verification failed; leave the router powered on for its 120-second automatic rollback")
    ssh(site, router, "touch /tmp/router-config-" + token + "/confirmed")
    print("Repair verified; automatic rollback cancelled")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=CONFIG)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate", help="Validate local intended settings; no SSH or NAS access")
    p = commands.add_parser("check", help="Read-only router configuration and network checks")
    p.add_argument("--network-only", action="store_true", help="HTTP and u3 health checks without router config reads")
    p = commands.add_parser("plan", help="Show changed UCI paths without values or writes")
    p.add_argument("router")
    p = commands.add_parser("apply", help="Preview by default; --execute performs a guarded repair")
    p.add_argument("router")
    p.add_argument("--execute", action="store_true")
    p = commands.add_parser("backup", help="Preview backup destination; --execute starts a manual backup")
    p.add_argument("router", nargs="?", default="all")
    p.add_argument("--execute", action="store_true")
    p.add_argument("--accept-baseline", action="store_true", help="After successful backup, retain core UCI settings privately on j2")
    args = parser.parse_args(argv)
    site = load_site(args.config)
    if args.command == "validate":
        print("Local intended settings valid. No router or NAS access performed.")
        return 0
    if args.command == "backup":
        names = list(site["routers"]) if args.router == "all" else [args.router]
        if any(n not in site["routers"] for n in names):
            raise Error("Unknown router")
        if not args.execute:
            print("Preview only: " + ", ".join(names) + " -> " + site["backup"]["ssh"] + ":" + site["backup"]["directory"])
            print("No backup or NAS access performed. Use --execute only when a backup is requested and SnapRAID is idle.")
            return 0
        backup(site, names, args.accept_baseline)
        return 0
    if args.command in ("plan", "apply"):
        if args.router not in site["routers"]:
            raise Error("Unknown router")
        apply(site, args.router, args.command == "apply" and args.execute)
        return 0
    failures = network_check(site)
    if not args.network_only:
        for name, router in site["routers"].items():
            try:
                info = inspect(site, router)
                items, approved = desired(site, name, router)
                if info["firmware"] != approved:
                    print(f"WARN {name}: firmware differs from the reviewed baseline")
                issues = check_info(router, info, items)
                for issue in issues:
                    print(f"FAIL {name}: {issue}")
                failures += len(issues)
                if not issues:
                    print(f"PASS {name}: managed settings and runtime interfaces")
            except Error as exc:
                print(f"FAIL {name}: {exc}")
                failures += 1
    return int(bool(failures))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (Error, ValueError, KeyError) as exc:
        # ValueError/KeyError details can contain private configuration values.
        print("ERROR: " + (str(exc) if isinstance(exc, Error) else "Invalid configuration or router response"), file=sys.stderr)
        sys.exit(2)
