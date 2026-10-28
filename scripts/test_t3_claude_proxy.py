"""Exercise T3's Claude launch boundary without model calls or real secrets."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class ClaudeProxyLauncherTest(unittest.TestCase):
    def test_sdk_arguments_keep_proxy_routing_and_scoped_telemetry(self):
        launcher = Path(__file__).with_name("t3-claude-proxy")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / ".config/agent-otel"
            config.mkdir(parents=True)
            (root / ".bash_secrets").write_text(
                'export ANTHROPIC_BASE_URL=https://proxy.invalid\n'
                'export ANTHROPIC_AUTH_TOKEN=fixture-token\n'
                'export ANTHROPIC_DEFAULT_OPUS_MODEL=claude-pro/claude-opus-5-5\n'
                'export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-pro/claude-haiku-4-5-20251001\n'
                'export UNRELATED_PRIVATE_VALUE=must-not-leak\n'
            )
            (config / "credentials").write_text("fixture:credential")
            (config / "env.sh").write_text(
                'export OTEL_EXPORTER_OTLP_ENDPOINT=https://collector.invalid\n'
                'export OTEL_EXPORTER_OTLP_HEADERS=fixture-header\n'
            )
            (config / "claude-settings.json").write_text('{}')
            binary = root / "claude"
            binary.write_text(
                '#!/usr/bin/env python3\n'
                'import json,os,sys\n'
                'print(json.dumps({"args":sys.argv[1:],"env":dict(os.environ)}))\n'
            )
            binary.chmod(0o700)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / ".config"),
                       PATH=f"{root}:{os.environ['PATH']}",
                       OTEL_EXPORTER_OTLP_LOGS_ENDPOINT="https://stale.invalid")
            cases = [
                (["--model", "claude-opus-5-5"], ["--model", "claude-pro/claude-opus-5-5"]),
                (["--model=claude-sonnet-5-5"], ["--model=claude-pro/claude-sonnet-5-5"]),
                (["--model", "claude-pro/claude-opus-5-5"], ["--model", "claude-pro/claude-opus-5-5"]),
                (["--fallback-model", "claude-haiku-5-5"], ["--fallback-model", "claude-pro/claude-haiku-5-5"]),
                (["--model", "claude-haiku-4-5"], ["--model", "claude-pro/claude-haiku-4-5-20251001"]),
                (["--model", "opus"], ["--model", "opus"]),
                (["--version"], ["--version"]),
            ]
            for supplied, expected in cases:
                with self.subTest(args=supplied):
                    result = subprocess.run(
                        ["python3", str(launcher), *supplied, "argument with spaces"],
                        env=env, capture_output=True, text=True, check=True,
                    )
                    data = json.loads(result.stdout)
                    self.assertEqual(data["args"], ["--settings", str(config / "claude-settings.json"),
                                                    *expected, "argument with spaces"])
                    child = data["env"]
                    self.assertEqual(child["ANTHROPIC_BASE_URL"], "https://proxy.invalid")
                    self.assertEqual(child["ANTHROPIC_AUTH_TOKEN"], "fixture-token")
                    self.assertEqual(child["OTEL_EXPORTER_OTLP_ENDPOINT"], "https://collector.invalid")
                    self.assertNotIn("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", child)
                    self.assertNotIn("UNRELATED_PRIVATE_VALUE", child)


if __name__ == "__main__":
    unittest.main()
