#!/usr/bin/env python3
"""Exercise real bootstrap credential creation with isolated Termux/PG fixtures."""
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest


@unittest.skipUnless(shutil.which("openssl") and shutil.which("flock"), "requires openssl and flock")
class DatabaseCredentialTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="artex-credential-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.home = self.root / "installation with spaces"
        (self.home / "config").mkdir(parents=True)
        self.password = self.home / "config/postgres.password"
        self.mock = self.root / "commands"
        self.mock.mkdir()
        self.repo = pathlib.Path(__file__).resolve().parents[2]
        payload = self.root / "payload"
        (payload / "termux").mkdir(parents=True)
        (payload / "skills").mkdir()
        for name in ("common", "start", "stop", "status"):
            shutil.copyfile(self.repo / "android/termux" / (name + ".sh"), payload / "termux" / (name + ".sh"))
        backend = payload / "apagent"
        backend.write_text("#!/usr/bin/env bash\nexit 0\n")
        backend.chmod(0o700)
        self.archive = self.root / "runtime.tar.gz"
        with tarfile.open(self.archive, "w:gz") as archive:
            for path in payload.iterdir():
                archive.add(path, arcname=path.name)
        self.command("id", "print('10000')\n")
        self.command("uname", "print('aarch64')\n")
        self.command("dpkg", "pass\n")
        self.command("pkg", """import os, pathlib, sys
if sys.argv[1] == 'install' and 'openssl-tool' in sys.argv:
    (pathlib.Path(os.environ['ARTEX_FIXTURE_ROOT']) / 'openssl-cli-installed').touch()
""")
        self.command("openssl", """import os, pathlib, sys
root = pathlib.Path(os.environ['ARTEX_FIXTURE_ROOT'])
if not (root / 'openssl-cli-installed').exists():
    print('openssl: command not found', file=sys.stderr)
    raise SystemExit(127)
if os.environ.get('ARTEX_FIXTURE_RANDOM_FAIL') == '1':
    print('partial failed output')
    raise SystemExit(1)
os.execv(os.environ['ARTEX_FIXTURE_OPENSSL'], [os.environ['ARTEX_FIXTURE_OPENSSL'], *sys.argv[1:]])
""")
        self.command("postgres", "print('postgres (PostgreSQL) 16.1')\n")
        self.command("initdb", """import os, pathlib, re, sys
path = pathlib.Path(next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--pwfile=')))
data = path.read_bytes()
assert re.fullmatch(rb'[0-9a-f]{48}\\n?', data), 'initdb received an empty/invalid password'
(pathlib.Path(os.environ['ARTEX_FIXTURE_ROOT']) / 'initdb-invoked').touch()
print('fixture: credential checked before stopping initdb', file=sys.stderr)
raise SystemExit(1)
""")
        os.symlink(sys.executable, self.mock / "python")
        self.env = dict(os.environ, ARTEX_HOME=str(self.home), ARTEX_FIXTURE_ROOT=str(self.root),
                        ARTEX_FIXTURE_OPENSSL=shutil.which("openssl"),
                        PATH=str(self.mock) + os.pathsep + os.environ["PATH"])

    def command(self, name, body):
        path = self.mock / name
        path.write_text("#!/usr/bin/env python3\n" + body)
        path.chmod(0o700)

    def bootstrap(self):
        result = subprocess.run(["bash", "-s", "--", "--runtime-file", str(self.archive)],
                                input=(self.repo / "android/termux/bootstrap.sh").read_text(),
                                env=self.env, text=True, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)  # The isolated initdb fixture intentionally stops here.
        return result

    def expect_checked_credential(self):
        result = self.bootstrap()
        self.assertTrue((self.root / "initdb-invoked").exists(), result.stdout + result.stderr)
        self.assertRegex(self.password.read_text(), r"^[0-9a-f]{48}\n?$")

    def test_cli_dependency_provides_a_fresh_credential(self):
        self.expect_checked_credential()
        self.assertEqual(self.password.stat().st_mode & 0o777, 0o600)

    def test_recovers_empty_file_left_by_missing_cli_before_cluster_creation(self):
        self.password.touch()
        self.expect_checked_credential()

    def test_valid_existing_credential_is_not_regenerated(self):
        original = "a" * 48 + "\n"
        self.password.write_text(original)
        self.env["ARTEX_FIXTURE_RANDOM_FAIL"] = "1"
        self.expect_checked_credential()
        self.assertEqual(self.password.read_text(), original)

    def test_failed_random_command_does_not_commit_partial_output(self):
        self.password.touch()
        self.env["ARTEX_FIXTURE_RANDOM_FAIL"] = "1"
        self.bootstrap()
        self.assertEqual(self.password.read_bytes(), b"")
        self.assertFalse((self.root / "initdb-invoked").exists())

    def test_empty_existing_cluster_credential_is_never_reset(self):
        self.password.touch()
        cluster = self.home / "postgres"
        cluster.mkdir()
        (cluster / "PG_VERSION").write_text("16\n")
        (cluster / ".artex-owned").write_text("managed\n")
        (cluster / "user-data").write_bytes(b"preserve existing data")
        self.bootstrap()
        self.assertEqual(self.password.read_bytes(), b"")
        self.assertEqual((cluster / "user-data").read_bytes(), b"preserve existing data")
        self.assertFalse((self.root / "initdb-invoked").exists())
        self.assertFalse((self.home / "config/config.json").exists())

    def test_invalid_nonempty_credential_is_preserved_and_rejected_before_initdb(self):
        original = b"custom credential must not be silently replaced\n"
        self.password.write_bytes(original)
        self.bootstrap()
        self.assertEqual(self.password.read_bytes(), original)
        self.assertFalse((self.root / "initdb-invoked").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
