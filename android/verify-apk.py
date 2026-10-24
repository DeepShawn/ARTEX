#!/usr/bin/env python3
"""Inspect the delivered APK/runtime; this does not replace Android device tests."""
import hashlib
import io
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def check_elf(data, interpreter=False, machine=183):
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    assert data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
    assert header[1:3] == (3, machine), "Unexpected ELF architecture or executable type"
    programs = [struct.unpack_from("<IIQQQQQQ", data, header[5] + i * header[9]) for i in range(header[10])]
    loads = [p for p in programs if p[0] == 1]
    assert loads and all(p[7] >= 16384 for p in loads), "ELF does not support 16KB pages"
    if interpreter:
        dynamic_linkers = [data[p[2]:p[2] + p[5]].rstrip(b"\0") for p in programs if p[0] == 3]
        assert dynamic_linkers == [b"/system/bin/linker64"], dynamic_linkers


def main():
    apk = pathlib.Path(sys.argv[1])
    with zipfile.ZipFile(apk) as archive:
        assert archive.testzip() is None, "APK ZIP CRC failure"
        assert "classes.dex" in archive.namelist(), "Application code missing"
        properties = dict(line.split("=", 1) for line in archive.read("assets/runtime.properties").decode().splitlines() if "=" in line)
        abi = properties["runtime.abi"]
        assert abi in ("arm64-v8a", "x86_64"), abi
        machine = 183 if abi == "arm64-v8a" else 62
        native = [name for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")]
        assert native == ["lib/" + abi + "/libartex_abi.so"], native
        check_elf(archive.read(native[0]), machine=machine)
        runtime = archive.read("assets/runtime.tar.gz")
        assert hashlib.sha256(runtime).hexdigest() == properties["runtime.sha256"], "Bundled runtime SHA256 mismatch"
        bootstrap = archive.read("assets/bootstrap.sh")
        assert b"--ready-url" in bootstrap and b"--foreground" in bootstrap, "Initialization protocol missing"
    with tarfile.open(fileobj=io.BytesIO(runtime), mode="r:gz") as archive:
        members = {}
        for member in archive.getmembers():
            path = pathlib.PurePosixPath(member.name)
            assert not path.is_absolute() and ".." not in path.parts, member.name
            assert member.isfile() or member.isdir(), "Runtime contains a link or special file"
            members[str(path)] = member
        for name in ("apagent", "VERSION", "LICENSE", "NOTICE", "config.example.json", "termux/bootstrap.sh", "termux/common.sh", "termux/start.sh", "termux/stop.sh", "termux/status.sh"):
            assert name in members, "Missing runtime file: " + name
        assert any(name.startswith("skills/") for name in members), "Bundled skills missing"
        assert not any(pathlib.PurePosixPath(name).name in ("jwt.key", "postgres.password", ".env", "config.json") for name in members), "Runtime contains generated credentials"
        version = archive.extractfile(members["VERSION"]).read().decode().strip()
        assert version == properties["runtime.version"], "Runtime version mismatch"
        backend = archive.extractfile(members["apagent"]).read()
        check_elf(backend, interpreter=True, machine=machine)
        assert members["apagent"].mode & 0o100, "Backend is not executable"
    reader = shutil.which("readelf")
    if not reader:
        raise SystemExit("Install binutils/readelf to verify Android system DNS linking")
    with tempfile.TemporaryDirectory(prefix="artex-apk-verify-") as directory:
        binary = pathlib.Path(directory) / "apagent"
        binary.write_bytes(backend)
        symbols = subprocess.check_output([reader, "--dyn-syms", "--wide", str(binary)], text=True)
        assert re.search(r"\bUND\s+getaddrinfo(?:@|\s|$)", symbols), "System DNS resolver is not linked"
        dynamic = subprocess.check_output([reader, "-d", str(binary)], text=True)
        libraries = set(re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic))
        assert "libc.so" in libraries and libraries <= {"libc.so", "libdl.so", "liblog.so", "libm.so"}, libraries
    print("PASS: APK contents, runtime SHA256,", abi, "Android ELF, system DNS, 16KB alignment and bootstrap protocol:", version)


if __name__ == "__main__":
    main()
