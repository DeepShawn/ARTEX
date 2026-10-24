#!/usr/bin/env bash
# Build the signed Android APK and its local Termux runtime without Gradle.
#
# Required signing inputs (keep outside the repository):
#   ANDROID_KEYSTORE=/private/artex-release.p12
#   ANDROID_KEYSTORE_PASSWORD_FILE=/private/keystore-password.txt
#   ANDROID_KEY_ALIAS=artex (default)
# Passwords can alternatively be supplied as ANDROID_KEYSTORE_PASSWORD and
# ANDROID_KEY_PASSWORD environment variables. Do not enable shell tracing.
#
# Optional inputs:
#   ANDROID_SDK_ROOT              SDK prepared by prepare-toolchain.sh
#   ANDROID_NDK_ROOT              Defaults to the prepared r28c NDK
#   APAGENT_BUILD_VERSION         Defaults to 0.3.17-android.3
#   ANDROID_VERSION_CODE          Defaults to 4
#   ANDROID_RUNTIME_ABI           arm64-v8a (release) or x86_64 (emulator tests)
#   APAGENT_SOURCE_REF            Defaults to android-v<Android-version>
#   APAGENT_SKIP_FRONTEND=1        Reuse an already exported production frontend
#   APAGENT_SKIP_NPM_CI=1          Reuse installed npm dependencies
#   GO=/path/to/go                Go compiler, defaults to go on PATH
#   SOURCE_DATE_EPOCH              Runtime archive timestamp for reproducible builds
set -euo pipefail

android_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$android_dir")"
cd "$repo_dir"
version="${APAGENT_BUILD_VERSION:-0.3.17-android.3}"
version="${version#v}"
version_code="${ANDROID_VERSION_CODE:-4}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-android\.[0-9]+$ ]] || { echo 'Expected an Android version such as 0.3.17-android.1' >&2; exit 1; }
[[ "$version_code" =~ ^[1-9][0-9]*$ ]] || { echo 'ANDROID_VERSION_CODE must be a positive integer' >&2; exit 1; }
sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/artex/android-sdk}}"
ndk_root="${ANDROID_NDK_ROOT:-$sdk_root/ndk/28.2.13676358}"
runtime_abi="${ANDROID_RUNTIME_ABI:-arm64-v8a}"
case "$runtime_abi" in
  arm64-v8a) go_arch=arm64; compiler_target=aarch64 ;;
  x86_64) go_arch=amd64; compiler_target=x86_64 ;;
  *) echo 'ANDROID_RUNTIME_ABI must be arm64-v8a or x86_64' >&2; exit 1 ;;
esac
android_cc="$ndk_root/toolchains/llvm/prebuilt/linux-x86_64/bin/${compiler_target}-linux-android26-clang"
build_tools="$sdk_root/build-tools/35.0.1"
android_jar="$sdk_root/platforms/android-35/android.jar"
go_binary="${GO:-go}"
work_dir="$android_dir/build"
source_dir="$android_dir/app/src/main"
assets_dir="$source_dir/assets"
output_dir="${APAGENT_PACKAGE_DIR:-$repo_dir/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
apk="$output_dir/artex-${version}-${runtime_abi}.apk"

for required in java keytool python3 zip tar sha256sum "$go_binary"; do
  command -v "$required" >/dev/null || { echo "Missing build dependency: $required" >&2; exit 1; }
done
java com.sun.tools.javac.Main -version
"$go_binary" version
if [ ! -x "$build_tools/aapt" ] || [ ! -f "$android_jar" ] || [ ! -x "$android_cc" ]; then
  ANDROID_SDK_ROOT="$sdk_root" bash "$android_dir/prepare-toolchain.sh"
fi
: "${ANDROID_KEYSTORE:?Set ANDROID_KEYSTORE to the private release keystore}"
test -f "$ANDROID_KEYSTORE"
if [ -n "${ANDROID_KEYSTORE_PASSWORD_FILE:-}" ]; then
  test -f "$ANDROID_KEYSTORE_PASSWORD_FILE"
  store_password="file:$ANDROID_KEYSTORE_PASSWORD_FILE"
elif [ -n "${ANDROID_KEYSTORE_PASSWORD:-}" ]; then
  export ANDROID_KEYSTORE_PASSWORD
  store_password='env:ANDROID_KEYSTORE_PASSWORD'
else
  echo 'Set ANDROID_KEYSTORE_PASSWORD_FILE or ANDROID_KEYSTORE_PASSWORD' >&2
  exit 1
fi
key_password_args=()
if [ -n "${ANDROID_KEY_PASSWORD_FILE:-}" ]; then
  test -f "$ANDROID_KEY_PASSWORD_FILE"
  key_password_args=(--key-pass "file:$ANDROID_KEY_PASSWORD_FILE")
elif [ -n "${ANDROID_KEY_PASSWORD:-}" ]; then
  export ANDROID_KEY_PASSWORD
  key_password_args=(--key-pass env:ANDROID_KEY_PASSWORD)
fi

test -f "$source_dir/AndroidManifest.xml"
test -f "$android_dir/termux/bootstrap.sh"
if [ "${APAGENT_SKIP_FRONTEND:-0}" != 1 ]; then
  command -v npm >/dev/null || { echo 'npm is required to export the frontend' >&2; exit 1; }
  if [ "${APAGENT_SKIP_NPM_CI:-0}" != 1 ]; then (cd web && npm ci); fi
  (cd web && NEXT_PUBLIC_MOCK=0 NEXT_PUBLIC_BASE_PATH='' NEXT_TELEMETRY_DISABLED=1 npm run build:static)
  rm -rf server/webui/dist
  mkdir -p server/webui/dist
  cp -R web/out/. server/webui/dist/
fi
test -f server/webui/dist/index.html
rm -rf "$work_dir"
mkdir -p "$work_dir/runtime" "$work_dir/generated" "$work_dir/classes" "$work_dir/dex" "$work_dir/res" "$work_dir/apk-native/lib/$runtime_abi" "$assets_dir"

echo "Building the Android $runtime_abi backend with the system DNS resolver"
GOOS=android GOARCH="$go_arch" CGO_ENABLED=1 \
  CC="$android_cc" \
  "$go_binary" build -tags embedui,sqlite_fts5 -trimpath \
  -ldflags "-s -w -buildid= -X main.version=$version -extldflags=-Wl,-z,max-page-size=16384" \
  -o "$work_dir/runtime/apagent" ./cmd/apagent
chmod 755 "$work_dir/runtime/apagent"
cp -R skills "$work_dir/runtime/skills"
cp -R "$android_dir/termux" "$work_dir/runtime/termux"
cp LICENSE NOTICE CHANGELOG.md SYSTEM_PROMPT_ENTRYPOINTS.md config.example.json "$work_dir/runtime/"
cp "$android_dir/README.md" "$work_dir/runtime/ANDROID-README.md"
cp "$android_dir/VALIDATION.md" "$work_dir/runtime/ANDROID-VALIDATION.md"
source_ref="${APAGENT_SOURCE_REF:-android-v${version}}"
printf 'Corresponding source: https://github.com/DeepShawn/ARTEX/tree/%s\nSource archive: https://github.com/DeepShawn/ARTEX/archive/refs/tags/%s.tar.gz\nBuild instructions: android/README.md and android/build.sh in the source tree.\nLicense: GNU Affero General Public License v3.0; see LICENSE.\n' \
  "$source_ref" "$source_ref" > "$work_dir/runtime/SOURCE.txt"
printf '%s\n' "$version" > "$work_dir/runtime/VERSION"
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
  archive_epoch="$SOURCE_DATE_EPOCH"
elif [ -e "$repo_dir/.git" ] && command -v git >/dev/null; then
  archive_epoch="$(git log -1 --format=%ct)"
else
  archive_epoch=0
fi
[[ "$archive_epoch" =~ ^[0-9]+$ ]] || { echo 'SOURCE_DATE_EPOCH must be an integer' >&2; exit 1; }
tar --sort=name --mtime="@$archive_epoch" --owner=0 --group=0 --numeric-owner \
  -C "$work_dir/runtime" -czf "$assets_dir/runtime.tar.gz" .
runtime_sha256="$(sha256sum "$assets_dir/runtime.tar.gz" | cut -d ' ' -f 1)"
printf 'runtime.version=%s\nruntime.sha256=%s\nruntime.abi=%s\n' "$version" "$runtime_sha256" "$runtime_abi" > "$assets_dir/runtime.properties"
cp "$android_dir/termux/bootstrap.sh" "$assets_dir/bootstrap.sh"
cp LICENSE "$assets_dir/LICENSE.txt"
cp NOTICE "$assets_dir/NOTICE.txt"
cp "$work_dir/runtime/SOURCE.txt" "$assets_dir/SOURCE.txt"

# The launcher delegates execution to Termux. This unloaded marker makes Android
# enforce the same ABI as the bundled runtime at installation time.
printf 'const char *artex_packaged_runtime_abi(void) { return "%s"; }\n' "$runtime_abi" > "$work_dir/abi.c"
"$android_cc" -shared -fPIC -nostdlib -Wl,-z,max-page-size=16384 \
  -Wl,--build-id=none -Wl,-soname,libartex_abi.so \
  -o "$work_dir/apk-native/lib/$runtime_abi/libartex_abi.so" "$work_dir/abi.c"

resource_args=()
if [ -d "$source_dir/res" ]; then resource_args=(-S "$source_dir/res"); fi
"$build_tools/aapt" package -f -m \
  -M "$source_dir/AndroidManifest.xml" -I "$android_jar" \
  "${resource_args[@]}" -J "$work_dir/generated" \
  -F "$work_dir/unsigned.apk" --auto-add-overlay \
  --min-sdk-version 26 --target-sdk-version 35 \
  --replace-version --version-code "$version_code" --version-name "$version"
python3 - "$source_dir/java" "$work_dir/generated" "$work_dir/java-sources.txt" <<'PY'
from pathlib import Path
import sys
files = sorted([*Path(sys.argv[1]).rglob('*.java'), *Path(sys.argv[2]).rglob('*.java')])
if not files:
    raise SystemExit('No Android Java sources found')
with open(sys.argv[3], 'w') as output:
    for path in files:
        output.write('"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"\n')
PY
java com.sun.tools.javac.Main -encoding UTF-8 -source 8 -target 8 \
  -bootclasspath "$android_jar:$build_tools/core-lambda-stubs.jar" \
  -d "$work_dir/classes" "@$work_dir/java-sources.txt"
java sun.tools.jar.Main --create --file "$work_dir/classes.jar" -C "$work_dir/classes" .
"$build_tools/d8" --release --min-api 26 --lib "$android_jar" \
  --output "$work_dir/dex" "$work_dir/classes.jar"
(cd "$work_dir/dex" && zip -q -X "$work_dir/unsigned.apk" classes*.dex)
# aapt transparently gunzips .gz assets and removes their suffix. Add the assets
# unchanged after aapt so runtime.tar.gz keeps both its filename and checksum.
(cd "$source_dir" && zip -q -X -r "$work_dir/unsigned.apk" assets -x assets/runtime.tar.gz \
  && zip -0 -q -X "$work_dir/unsigned.apk" assets/runtime.tar.gz)
(cd "$work_dir/apk-native" && zip -0 -q -X "$work_dir/unsigned.apk" "lib/$runtime_abi/libartex_abi.so")
"$build_tools/zipalign" -P 16 -f 4 "$work_dir/unsigned.apk" "$work_dir/aligned.apk"
"$build_tools/apksigner" sign --ks "$ANDROID_KEYSTORE" \
  --ks-key-alias "${ANDROID_KEY_ALIAS:-artex}" --ks-pass "$store_password" \
  "${key_password_args[@]}" --out "$apk" "$work_dir/aligned.apk"
"$build_tools/apksigner" verify --verbose --print-certs "$apk"
"$build_tools/zipalign" -c -P 16 4 "$apk"
"$build_tools/aapt" dump badging "$apk" > "$work_dir/apk-badging.txt"
python3 - "$work_dir/apk-badging.txt" "$version" "$version_code" "$runtime_abi" <<'PY'
from pathlib import Path
import sys
badging = Path(sys.argv[1]).read_text()
assert "name='io.github.deepshawn.artex'" in badging, 'Unexpected application ID'
assert "versionName='" + sys.argv[2] + "'" in badging, 'APK version name was not applied'
assert "versionCode='" + sys.argv[3] + "'" in badging, 'APK version code was not applied'
assert "sdkVersion:'26'" in badging, 'Unexpected minimum Android API'
assert "targetSdkVersion:'35'" in badging, 'Unexpected target Android API'
assert "native-code: '" + sys.argv[4] + "'" in badging, 'APK must require the packaged runtime ABI'
PY
sed -n '1,5p' "$work_dir/apk-badging.txt"
(cd "$output_dir" && sha256sum "$(basename "$apk")" > "$(basename "$apk").sha256")
printf 'Signed APK: %s\nRuntime SHA256: %s\n' "$apk" "$runtime_sha256"
