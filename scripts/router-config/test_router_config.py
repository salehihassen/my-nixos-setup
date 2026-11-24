import contextlib
import copy
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import router_config as rc


def fixture():
    return {
        "firmware": "4.10.2", "board": {"model": "GL.iNet GL-BE9300"},
        "configs": {
            "network": [
                {"name": "lan", "type": "interface", "options": {"ipaddr": "192.168.50.1", "netmask": "255.255.255.0"}},
                {"name": "iot", "type": "interface", "options": {"ipaddr": "192.168.60.1", "netmask": "255.255.255.0"}},
            ],
            "dhcp": [{"name": "@host[0]", "type": "host", "options": {"mac": "02:00:00:00:00:04", "ip": "192.168.50.186"}}],
        },
        "interfaces": {"interface": [
            {"interface": "lan", "up": True, "ipv4-address": [{"address": "192.168.50.1", "mask": 24}]},
            {"interface": "iot", "up": True, "ipv4-address": [{"address": "192.168.60.1", "mask": 24}]},
        ]},
    }


class RouterConfigTests(unittest.TestCase):
    def setUp(self):
        self.site = json.loads(Path(__file__).with_name("site.example.json").read_text())
        self.router = self.site["routers"]["main"]

    def test_subnet_collision_is_detected_even_when_addresses_differ(self):
        info = fixture()
        info["interfaces"]["interface"][1]["ipv4-address"][0]["address"] = "192.168.50.20"
        self.assertEqual(rc.overlaps(info), [("lan", "iot")])
        self.assertTrue(any("overlap" in i for i in rc.check_info(self.router, info, self.router["desired"])))

    def test_desired_networks_cannot_overlap(self):
        self.router["subnets"]["iot"] = "192.168.50.20/24"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "site.json"
            path.write_text(json.dumps(self.site))
            with self.assertRaises(rc.Error):
                rc.load_site(path)

    def test_healthy_state_has_no_diff(self):
        self.assertEqual(rc.check_info(self.router, fixture(), self.router["desired"]), [])

    def test_mac_case_does_not_cause_false_drift(self):
        info = fixture()
        info["configs"]["dhcp"][0]["options"]["mac"] = "02:AB:00:00:00:04"
        self.router["desired"][2]["match"]["value"] = "02:ab:00:00:00:04"
        self.router["desired"][2]["options"]["mac"] = "02:ab:00:00:00:04"
        self.assertEqual(rc.differences(info, self.router["desired"]), [])

    def test_duplicate_ip_reservations_are_flagged(self):
        info = fixture()
        info["configs"]["dhcp"].append({"name": "other", "type": "host", "options": {"ip": "192.168.50.186", "mac": "02:00:00:00:00:09"}})
        self.assertIn("multiple DHCP reservations use the same address", rc.check_info(self.router, info, self.router["desired"]))

    def test_reservation_uses_dhcp_mac_not_other_wifi_mac(self):
        info = fixture()
        info["configs"]["dhcp"][0]["options"]["mac"] = "02:00:00:00:00:05"
        changes = rc.differences(info, self.router["desired"])
        self.assertTrue(changes[0][1]["new"])
        self.assertEqual(changes[0][1]["name"], "office_beryl")

    def test_duplicate_reservations_fail_instead_of_selecting_arbitrarily(self):
        info = fixture()
        info["configs"]["dhcp"].append(copy.deepcopy(info["configs"]["dhcp"][0]))
        with self.assertRaises(rc.Error):
            rc.differences(info, self.router["desired"])

    def test_missing_or_migrated_section_fails(self):
        info = fixture()
        info["configs"]["network"][1]["type"] = "device"
        with self.assertRaises(rc.Error):
            rc.differences(info, self.router["desired"])

    def test_firmware_change_blocks_execute_without_writes(self):
        info = fixture()
        info["firmware"] = "4.12.0"
        info["configs"]["network"][1]["options"]["ipaddr"] = "192.168.50.1"
        with patch.object(rc, "inspect", return_value=info), patch.object(rc, "desired", return_value=(self.router["desired"], "4.10.2")), patch.object(rc, "ssh") as ssh:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(rc.Error):
                rc.apply(self.site, "main", True)
            ssh.assert_not_called()

    def test_plan_never_writes_or_backs_up(self):
        info = fixture()
        info["configs"]["network"][1]["options"]["ipaddr"] = "192.168.50.1"
        with patch.object(rc, "inspect", return_value=info), patch.object(rc, "desired", return_value=(self.router["desired"], "4.10.2")), patch.object(rc, "ssh") as ssh, patch.object(rc, "backup") as backup:
            with contextlib.redirect_stdout(io.StringIO()):
                rc.apply(self.site, "main", False)
            ssh.assert_not_called()
            backup.assert_not_called()

    def test_bare_backup_is_only_preview_and_never_contacts_nas(self):
        with patch.object(rc, "load_site", return_value=self.site), patch.object(rc, "ssh") as ssh, patch.object(rc, "backup") as backup:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(rc.main(["backup", "--accept-baseline"]), 0)
            ssh.assert_not_called()
            backup.assert_not_called()

    def test_nas_preflight_failure_prevents_router_backup(self):
        with patch.object(rc.shutil, "which", return_value="/age"), patch.object(Path, "is_file", return_value=True), patch.object(rc, "nas_preflight", side_effect=rc.Error("SnapRAID busy")), patch.object(rc, "inspect") as inspect:
            with self.assertRaises(rc.Error):
                rc.backup(self.site, ["main"])
            inspect.assert_not_called()

    def test_model_mismatch_is_rejected(self):
        info = fixture()
        info["board"]["model"] = "GL-MT3000"
        with patch.object(rc, "ssh", return_value=json.dumps(info).encode()), self.assertRaises(rc.Error):
            rc.inspect(self.site, self.router)

    def test_no_desktop_keyring_fallback(self):
        with patch.dict(os.environ, {"SSH_AUTH_SOCK": "/run/user/1000/gcr/ssh"}), patch.object(rc, "run") as run:
            with self.assertRaises(rc.Error):
                rc.ssh(self.site, self.router, "true")
            run.assert_not_called()

    def test_ssh_uses_batch_mode_and_selected_agent(self):
        with patch.dict(os.environ, {"SSH_AUTH_SOCK": "/tmp/unlocked-agent"}), patch.object(rc, "run", return_value=b"ok") as run:
            rc.ssh(self.site, self.router, "true")
        args = run.call_args.args[0]
        self.assertIn("BatchMode=yes", args)
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("IdentityAgent=/tmp/unlocked-agent", args)

    def test_repair_quotes_secrets_and_arms_rollback_before_changes(self):
        secret = "value'; touch /tmp/NOT-RUN; echo '$(false)`false`"
        section = {"name": "wifi5g", "type": "wifi-iface", "options": {}}
        changes = [("wireless", section, "key", None, secret)]
        script = rc.repair_script(changes, "a" * 32)
        self.assertLess(script.index(b"nohup sh"), script.index(b"uci set"))
        self.assertIn(b"sleep 120", script)
        self.assertIn(b"uci changes wireless", script)
        self.assertIn(b"router-config-apply.lock", script)
        self.assertEqual(subprocess.run(["sh", "-n"], input=script, capture_output=True).returncode, 0)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc.print_plan(changes)
        self.assertNotIn(secret, out.getvalue())
        command = next(line for line in script.decode().splitlines() if line.startswith("uci set "))
        import shlex
        self.assertEqual(shlex.split(command)[2], "wireless.wifi5g.key=" + secret)

    def test_network_mode_switch_is_not_faked_by_uci(self):
        change = [("glconfig", {"name": "general", "type": "service"}, "mode", "router", "wds")]
        with self.assertRaises(rc.Error):
            rc.repair_script(change, "a" * 32)

    def test_rollback_restores_file_and_discards_uncommitted_delta(self):
        token = "a" * 32
        change = [("dhcp", {"name": "lan", "type": "dhcp"}, "start", "100", "200")]
        script = rc.repair_script(change, token).decode()
        rollback = script.split("<<'ROLLBACK'\n", 1)[1].split("\nROLLBACK\n", 1)[0]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            saved = root / "saved"
            live = root / "live"
            lock = root / "lock"
            for path in (saved, live, lock):
                path.mkdir()
            (saved / "dhcp").write_text("original configuration")
            (live / "dhcp").write_text("partially committed configuration")
            staged = root / "staged"
            staged.write_text("uncommitted delta")
            uci = root / "uci"
            uci.write_text('#!/bin/sh\n[ "$*" = "-q revert dhcp" ] || exit 1\nunlink "$STAGED"\n')
            uci.chmod(0o700)
            rollback = rollback.replace("sleep 120", ":").replace(
                "/tmp/router-config-apply.lock", str(lock)).replace(
                "/tmp/router-config-" + token, str(saved)).replace(
                "/etc/config/", str(live) + "/").replace(
                "/etc/init.d/dnsmasq restart", ":")
            subprocess.run(["sh"], input=rollback.encode(), capture_output=True, check=True,
                           env=dict(os.environ, PATH=str(root) + ":" + os.environ["PATH"], STAGED=str(staged)))
            self.assertEqual((live / "dhcp").read_text(), "original configuration")
            self.assertFalse(staged.exists())
            self.assertFalse(lock.exists())

    def test_wds_repair_uses_saved_credentials_in_memory_and_vendor_connect(self):
        change = [("repeater", {"name": "@main[0]", "type": "main"}, "disabled", "1", "0")]
        script = rc.repair_script(change, "a" * 32)
        self.assertIn(b"con:call('repeater', 'connect'", script)
        self.assertIn(b"key=selected.key", script)
        self.assertEqual(subprocess.run(["sh", "-n"], input=script, capture_output=True).returncode, 0)

    def test_successful_apply_is_verified_before_confirming(self):
        before = fixture()
        before["configs"]["network"][1]["options"]["ipaddr"] = "192.168.50.1"
        with patch.object(rc, "inspect", side_effect=[before, fixture()]), patch.object(rc, "desired", return_value=(self.router["desired"], "4.10.2")), patch.object(rc, "ssh") as ssh, patch("time.sleep"), contextlib.redirect_stdout(io.StringIO()):
            rc.apply(self.site, "main", True)
        self.assertEqual(ssh.call_count, 2)
        self.assertTrue(ssh.call_args.args[2].startswith("touch /tmp/router-config-"))

    def test_failed_verification_does_not_cancel_rollback(self):
        info = fixture()
        info["configs"]["network"][1]["options"]["ipaddr"] = "192.168.50.1"
        with patch.object(rc, "inspect", return_value=info), patch.object(rc, "desired", return_value=(self.router["desired"], "4.10.2")), patch.object(rc, "ssh") as ssh, patch("time.sleep"), contextlib.redirect_stdout(io.StringIO()), self.assertRaises(rc.Error):
            rc.apply(self.site, "main", True)
        self.assertEqual(ssh.call_count, 1)

    def test_bundle_is_complete_and_native_archive_is_checked(self):
        native = io.BytesIO()
        with tarfile.open(fileobj=native, mode="w:gz") as tar:
            member = tarfile.TarInfo("etc/config/network")
            member.size = 3
            tar.addfile(member, io.BytesIO(b"uci"))
        bundle = rc.make_bundle("main", self.router, fixture(), native.getvalue(), b"package - version\n", b"/etc/config/network\n")
        with tarfile.open(fileobj=io.BytesIO(bundle)) as tar:
            self.assertEqual(set(tar.getnames()), {"metadata.json", "inspection.json", "native-backup.tar.gz", "installed-packages.txt", "backup-file-list.txt"})
        with self.assertRaises(rc.Error):
            rc.validate_archive(b"not a backup")

    def test_baseline_is_private_and_does_not_write_to_nas(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(rc, "STATE", Path(tmp) / "state"), patch.object(rc, "ssh") as ssh:
            rc.capture_baseline("main", self.router, fixture())
            path = rc.STATE / "main.baseline.json"
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            ssh.assert_not_called()

    def test_explicit_site_policy_overrides_an_older_baseline_once(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(rc, "STATE", Path(tmp) / "state"):
            info = fixture()
            info["configs"]["dhcp"][0]["options"]["ip"] = "192.168.50.200"
            rc.capture_baseline("main", self.router, info)
            items, _ = rc.desired(self.site, "main", self.router)
            self.assertEqual(rc.differences(fixture(), items), [])

    @unittest.skipUnless(shutil.which("age") and shutil.which("ssh-keygen"), "SSH/age integration dependencies unavailable")
    def test_ssh_recipient_encryption_round_trip_with_synthetic_keys(self):
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / "test.key"
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], capture_output=True, check=True)
            secret = b"SYNTHETIC-CONFIG-NOT-A-LIVE-BACKUP"
            encrypted = rc.run(["age", "-R", str(key) + ".pub"], secret)
            self.assertNotIn(secret, encrypted)
            self.assertEqual(rc.run(["age", "-d", "-i", str(key)], encrypted), secret)

    def test_upload_checks_pool_and_sync_and_atomically_publishes(self):
        self.site["backup"]["directory"] = "/mnt/pool/vault/with 'quotes/routers"
        with patch.object(rc, "ssh") as ssh:
            rc.upload(self.site, "test.tar.gz.age", b"encrypted")
        command = ssh.call_args.args[2]
        self.assertIn("pgrep -x snapraid", command)
        self.assertIn("findmnt -rn", command)
        self.assertIn("sha256sum", command)
        self.assertIn("\nln ", command)
        self.assertEqual(subprocess.run(["sh", "-n"], input=command.encode(), capture_output=True).returncode, 0)
        self.assertEqual(ssh.call_args.args[3], b"encrypted")

    def test_failed_upload_never_promotes_baseline(self):
        with patch.object(rc.shutil, "which", return_value="/age"), patch.object(Path, "is_file", return_value=True), patch.object(rc, "nas_preflight"), patch.object(rc, "inspect", return_value=fixture()), patch.object(rc, "desired", return_value=(self.router["desired"], "4.10.2")), patch.object(rc, "ssh", return_value=b"native"), patch.object(rc, "make_bundle", return_value=b"bundle"), patch.object(rc, "run", return_value=b"encrypted"), patch.object(rc, "upload", side_effect=rc.Error("upload failed")), patch.object(rc, "capture_baseline") as capture:
            with self.assertRaises(rc.Error):
                rc.backup(self.site, ["main"], accept_baseline=True)
            capture.assert_not_called()

    @unittest.skipUnless(shutil.which("age") and shutil.which("age-keygen"), "age integration dependencies unavailable")
    def test_age_encryption_round_trip_with_synthetic_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / "test.key"
            subprocess.run(["age-keygen", "-o", str(key)], capture_output=True, check=True)
            recipient = subprocess.run(["age-keygen", "-y", str(key)], capture_output=True, check=True).stdout
            public = Path(tmp) / "recipient.txt"
            public.write_bytes(recipient)
            secret = b"SYNTHETIC-ROUTER-CONFIG-NOT-A-LIVE-BACKUP"
            encrypted = rc.run(["age", "-R", str(public)], secret)
            self.assertNotIn(secret, encrypted)
            self.assertEqual(rc.run(["age", "-d", "-i", str(key)], encrypted), secret)


if __name__ == "__main__":
    unittest.main()
