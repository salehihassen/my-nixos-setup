"""Command-contract tests: no real Nix, sudo, networking, or activation."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'checkout with spaces'
        (self.root / 'scripts').mkdir(parents=True)
        self.script = self.root / 'scripts/nixos-maintain.sh'
        shutil.copyfile(Path(__file__).with_name('nixos-maintain.sh'), self.script)
        self.outside = Path(self.temp.name) / 'unrelated'
        self.outside.mkdir()
        self.bin = Path(self.temp.name) / 'bin'
        self.bin.mkdir()
        self.log = Path(self.temp.name) / 'calls.jsonl'
        stub = '''#!{python}
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as stream:
    stream.write(json.dumps([name, args, os.getcwd()]) + '\\n')
if os.environ.get('FAIL_COMMAND') == name and (not os.environ.get('FAIL_ARGUMENT') or os.environ['FAIL_ARGUMENT'] in args):
    sys.exit(37)
if name == 'hostname':
    print('j2')
elif name == 'nix' and args[0] == 'eval':
    print('b1\\nj2', end='')
'''.format(python=shutil.which('python3'))
        for name in ('nix', 'nixos-rebuild', 'sudo', 'hostname', 'git'):
            path = self.bin / name
            path.write_text(stub)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        CALL_LOG=str(self.log))

    def run_command(self, *args, **env):
        result = subprocess.run(['bash', str(self.script), *args], cwd=self.outside,
                                env=dict(self.env, **env), text=True, capture_output=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return result, calls

    def test_build_uses_checkout_and_hostname_without_root(self):
        result, calls = self.run_command('build')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ['hostname', 'nix', 'nixos-rebuild'])
        self.assertEqual(calls[-1], ['nixos-rebuild', ['build', '--flake', str(self.root) + '#j2',
                         '--no-update-lock-file', '--max-jobs', '2', '--cores', '4'], str(self.root)])
        self.assertEqual(calls[1][1][-1], str(self.root) + '#nixosConfigurations')

    def test_explicit_host_does_not_query_hostname(self):
        result, calls = self.run_command('build', 'b1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ['nix', 'nixos-rebuild'])
        self.assertIn(str(self.root) + '#b1', calls[-1][1])

    def test_check_is_explicit_and_does_not_build_or_elevate(self):
        result, calls = self.run_command('check', 'j2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ['nix', 'nix'])
        self.assertEqual(calls[-1][1], ['flake', 'check', '--no-build', '--no-update-lock-file', str(self.root)])

    def test_only_explicit_activation_operations_elevate(self):
        for operation in ('test', 'switch', 'boot'):
            with self.subTest(operation=operation):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_command(operation, 'j2')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call[0] for call in calls], ['nix', 'sudo'])
                self.assertEqual(calls[-1][1][:2], ['nixos-rebuild', operation])
                self.assertIn(str(self.root) + '#j2', calls[-1][1])

    def test_update_is_scoped_checked_built_and_never_activated(self):
        result, calls = self.run_command('update', 'b1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in calls], ['nix', 'nix', 'git', 'nix', 'nixos-rebuild'])
        self.assertEqual(calls[1][1], ['flake', 'update', 'nixpkgs', 'home-manager', '--flake', str(self.root)])
        self.assertEqual(calls[2][1], ['-C', str(self.root), 'diff', '--', 'flake.lock'])
        self.assertEqual(calls[-1][1][0], 'build')
        self.assertIn(str(self.root) + '#b1', calls[-1][1])

    def test_unknown_host_is_rejected_before_update_or_activation(self):
        for operation in ('update', 'switch'):
            with self.subTest(operation=operation):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_command(operation, 'missing')
                self.assertEqual(result.returncode, 2)
                self.assertIn('Unknown host', result.stderr)
                self.assertEqual([call[0] for call in calls], ['nix'])

    def test_invalid_arguments_do_not_invoke_nix(self):
        for args in ((), ('oops',), ('build', 'j2', 'extra'), ('build', 'j2#bad'), ('build', '--impure'), ('build', '')):
            with self.subTest(args=args):
                result, calls = self.run_command(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, [])

    def test_failure_stops_update_at_each_step(self):
        cases = [('nix', 'eval', 1), ('nix', 'update', 2), ('git', '', 3),
                 ('nix', 'check', 4), ('nixos-rebuild', '', 5)]
        for command, argument, count in cases:
            with self.subTest(command=command, argument=argument):
                self.log.unlink(missing_ok=True)
                result, calls = self.run_command('update', 'j2', FAIL_COMMAND=command, FAIL_ARGUMENT=argument)
                self.assertEqual(result.returncode, 37, result.stderr)
                self.assertEqual(len(calls), count)
                self.assertNotIn('sudo', [call[0] for call in calls])


if __name__ == '__main__':
    unittest.main()
