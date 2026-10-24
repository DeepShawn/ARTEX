#!/usr/bin/env bash
# Minimal Linux SDK and NDK for the Java launcher and Android Go runtime.
# Pinned SHA256 hashes follow an initial check against Google's repository2-3.xml.
set -euo pipefail

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/artex/android-sdk}}"
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) ;;
  *) echo 'This toolchain setup supports Linux x86_64 build hosts.' >&2; exit 1 ;;
esac
for required in curl unzip sha256sum python3 java; do
  command -v "$required" >/dev/null || { echo "Missing build dependency: $required" >&2; exit 1; }
done
java com.sun.tools.javac.Main -version >/dev/null
mkdir -p "$sdk_root/.downloads"

install_package() {
  local archive="$1" expected_sha256="$2" destination="$3" marker="$4"
  shift 4
  if [ -f "$destination/$marker" ]; then
    return
  fi
  local cached="$sdk_root/.downloads/$archive"
  if [ ! -f "$cached" ] || ! printf '%s  %s\n' "$expected_sha256" "$cached" | sha256sum -c - >/dev/null 2>&1; then
    echo "Downloading official Android SDK package: $archive"
    curl --fail --location --retry 3 --output "$cached.part" "https://dl.google.com/android/repository/$archive"
    printf '%s  %s\n' "$expected_sha256" "$cached.part" | sha256sum -c -
    mv "$cached.part" "$cached"
  fi
  local staging
  staging="$(mktemp -d "$sdk_root/.install.XXXXXX")"
  unzip -q "$cached" "$@" -d "$staging"
  local package_root
  package_root="$(python3 - "$staging" "$marker" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
marker = sys.argv[2]
candidates = [root] + [entry for entry in root.iterdir() if entry.is_dir()]
packages = [path for path in candidates if (path / marker).is_file()]
if len(packages) != 1:
    raise SystemExit('Unexpected Android SDK archive structure')
print(packages[0])
PY
)"
  mkdir -p "$(dirname "$destination")"
  if [ -e "$destination" ]; then
    echo "Refusing to replace incomplete SDK directory: $destination" >&2
    rm -rf "$staging"
    exit 1
  fi
  mv "$package_root" "$destination"
  rm -rf "$staging"
}

install_package build-tools_r35.0.1_linux.zip 5993499f3229a021b89f87088c57242aeefaa62316bf3d69da7de40bfd5350f1 "$sdk_root/build-tools/35.0.1" aapt
install_package platform-35_r02.zip 0988cacad01b38a18a47bac14a0695f246bc76c1b06c0eeb8eb0dc825ab0c8e0 "$sdk_root/platforms/android-35" android.jar
install_package android-ndk-r28c-linux.zip dfb20d396df28ca02a8c708314b814a4d961dc9074f9a161932746f815aa552f \
  "$sdk_root/ndk/28.2.13676358" toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang \
  'android-ndk-r28c/toolchains/llvm/prebuilt/linux-x86_64/*' \
  'android-ndk-r28c/source.properties' 'android-ndk-r28c/meta/*'
"$sdk_root/build-tools/35.0.1/aapt" version
"$sdk_root/build-tools/35.0.1/apksigner" version
"$sdk_root/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang" --version | sed -n '1p'
printf 'Android SDK ready: %s\n' "$sdk_root"
