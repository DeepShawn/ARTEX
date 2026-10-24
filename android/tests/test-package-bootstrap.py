#!/usr/bin/env python3
"""Exercise the bootstrap against real dpkg conffile prompts in isolated roots.

No host packages are configured or installed. Termux pkg/network/architecture
are fixtures; this does not replace a test on an Android device.
"""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("dpkg") and shutil.which("dpkg-deb"), "requires dpkg and dpkg-deb")
class PackageBootstrapTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="artex-dpkg-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.installed = self.root / "isolated-root"
        self.installed.mkdir()
        self.dpkg = shutil.which("dpkg")
        self.packages = []
        for version in ("1.0", "2.0"):
            source = self.root / version
            (source / "DEBIAN").mkdir(parents=True)
            (source / "DEBIAN").chmod(0o755)
            (source / "etc").mkdir()
            (source / "DEBIAN/control").write_text(
                "Package: artex-test-conffile\nVersion: " + version + "\n"
                "Architecture: all\nMaintainer: ARTEX test <test@example.invalid>\n"
                "Description: isolated configuration prompt regression fixture\n")
            (source / "DEBIAN/conffiles").write_text("/etc/artex-test.conf\n")
            (source / "etc/artex-test.conf").write_text("maintainer version " + version + "\n")
            archive = self.root / (version + ".deb")
            built = subprocess.run(["dpkg-deb", "--build", str(source), str(archive)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            self.packages.append(archive)
        result = self.run_dpkg("--install", str(self.packages[0]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.config = self.installed / "etc/artex-test.conf"
        self.config.write_text("user configuration to preserve\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.write_command("id", "print('10000')\n")
        self.write_command("uname", "print('aarch64')\n")
        self.write_command("dpkg", """import os, pathlib, subprocess, sys
marker = pathlib.Path(os.environ['FIXTURE_ROOT']) / 'fail-configure-once'
if marker.exists():
    marker.unlink()
    raise SystemExit(1)
raise SystemExit(subprocess.call([os.environ['FIXTURE_DPKG'], '--root=' + os.environ['FIXTURE_INSTALLED'], '--log=' + os.environ['FIXTURE_ROOT'] + '/dpkg.log', '--force-not-root', *sys.argv[1:]]))
""")
        self.write_command("pkg", """import os, pathlib, subprocess, sys
args = sys.argv[1:]
assert os.environ.get('DEBIAN_FRONTEND') == 'noninteractive'
assert os.environ.get('UCF_FORCE_CONFFOLD') == '1'
if args[0] == 'update':
    raise SystemExit(0)
assert args[0] == 'install', args
options = [arg.split('=', 1)[1] for arg in args if arg.startswith('Dpkg::Options::=')]
command = [os.environ['FIXTURE_DPKG'], '--root=' + os.environ['FIXTURE_INSTALLED'], '--log=' + os.environ['FIXTURE_ROOT'] + '/dpkg.log', '--force-not-root', *options]
if '--fix-broken' in args:
    (pathlib.Path(os.environ['FIXTURE_ROOT']) / 'recovered').touch()
    command += ['--configure', '-a']
else:
    assert 'openssl' in args and 'postgresql' in args, args
    command += ['--install', os.environ['FIXTURE_PACKAGE']]
raise SystemExit(subprocess.call(command))
""")

    def write_command(self, name, source):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + source)
        path.chmod(0o700)

    def run_dpkg(self, *args):
        return subprocess.run([self.dpkg, "--root=" + str(self.installed), "--log=" + str(self.root / "dpkg.log"), "--force-not-root", *args],
                              stdin=subprocess.DEVNULL, capture_output=True, text=True)

    def bootstrap(self):
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   ARTEX_HOME=str(self.root / "artex"), FIXTURE_ROOT=str(self.root),
                   FIXTURE_DPKG=self.dpkg, FIXTURE_INSTALLED=str(self.installed),
                   FIXTURE_PACKAGE=str(self.packages[1]))
        script = pathlib.Path(__file__).resolve().parents[1] / "termux/bootstrap.sh"
        # Match the APK's bash -s transport: children must not consume this stdin.
        result = subprocess.run(["bash", "-s", "--", "--runtime-file", str(self.root / "missing-runtime")],
                                input=script.read_text(), env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("Runtime file does not exist", result.stderr, result.stdout + result.stderr)
        self.assertEqual(self.config.read_text(), "user configuration to preserve\n")
        state = self.run_dpkg("--status", "artex-test-conffile")
        self.assertIn("Status: install ok installed", state.stdout)
        self.assertIn("Version: 2.0", state.stdout)

    def test_upgrade_keeps_modified_configuration_without_stdin(self):
        self.bootstrap()

    def test_recovers_the_reported_conffile_eof_failure(self):
        broken = self.run_dpkg("--install", str(self.packages[1]))
        self.assertNotEqual(broken.returncode, 0)
        self.assertIn("end of file on stdin at conffile prompt", broken.stderr)
        self.bootstrap()

    def test_dependency_repair_uses_the_same_noninteractive_options(self):
        (self.root / "fail-configure-once").touch()
        self.bootstrap()
        self.assertTrue((self.root / "recovered").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
