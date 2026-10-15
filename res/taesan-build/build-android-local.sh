#!/bin/zsh
# 태산 원격지원 Android APK 로컬 빌드 — macOS(arm64) 호스트. 접속하는 쪽(양방향) 앱만 만든다.
#
# 사용:  zsh res/taesan-build/build-android-local.sh [커밋·브랜치·태그] [local|release]   (기본 main, local)
# 결과:  ~/taesan-build/taesan-<버전>-android-<대상>.apk, 로그는 ~/taesan-build/logs/
#        + ~/taesan-build/dist/<버전>-<sha9>-<대상>/taesan-<버전>-android-<대상>.apk 와 manifest-android.txt
#
# 원칙
# - 중계 서버: ~/taesan-build/server.env(git 밖, 권한 600)의 TAESAN_RENDEZVOUS_SERVER·TAESAN_RS_PUB_KEY 를 컴파일 때 넣는다.
# - release: ref 는 origin 에 푸시된 taesan-v* 태그만 받는다. 서명 = 릴리즈 키(~/taesan-build/keys/android-release.properties),
#   서명 지문은 ~/taesan-build/keys/android-release.sha256 과 같아야 한다. versionCode = TAESAN_VERSION_CODE(숫자, 필수).
#   dist 에 NOTICE·LICENCE·THIRD_PARTY_NOTICES-android.txt. cargo-about 0.6.4 가 있어야 한다.
# - 작업 폴더는 건드리지 않는다. 별도 git worktree 에서 빌드하고 cargo target 도 분리한다.
#
# 전제(한 번 설치해 둔 것):
#   rustup + 1.75(타깃 aarch64-linux-android, armv7-linux-androideabi),
#   cargo-ndk 3.1.2 / cargo-expand 1.0.95 / flutter_rust_bridge_codegen 1.80.1(--features uuid),
#   Flutter 3.22.3(브리지)·3.24.5(앱) — fvm(~/fvm/versions/<버전>) 또는 ~/flutter-sdks/<버전>.
#   3.24.5 는 처음 빌드 때 ~/taesan-build/flutter-3.24.5 로 복사해 패치한다(원본은 건드리지 않는다),
#   ~/vcpkg-android(microsoft/vcpkg 120deac, bootstrap 완료), Android SDK + NDK r28c(28.2.13676358),
#   JDK 17(brew openjdk@17), Xcode Command Line Tools, brew: nasm pkgconf autoconf automake libtool
set -u
R="${TAESAN_CLIENT:-$HOME/Documents/GitHub/taesan-remote}"
OUT="$HOME/taesan-build"
W="$OUT/wt-android"
LOG="$OUT/logs"; mkdir -p "$LOG"
BASE="${1:-main}"
TARGET="${2:-local}"
case "$TARGET" in local|release) ;; *) echo "FAIL: 대상은 local 또는 release"; exit 1 ;; esac
KEYS="$OUT/keys"
# Flutter SDK: fvm 이 있으면 그쪽, 없으면 ~/flutter-sdks.
fl() { [ -x "$HOME/fvm/versions/$1/bin/flutter" ] && echo "$HOME/fvm/versions/$1" || echo "$HOME/flutter-sdks/$1"; }
FL_BRIDGE="${TAESAN_FLUTTER_BRIDGE:-$(fl 3.22.3)}"
# 앱 빌드용 3.24.5 는 드롭다운 패치(.github/patches)가 필요하다. 공용 SDK 를 고치지 않도록 전용 복사본에만 적용한다.
FL_APP="${TAESAN_FLUTTER_APP:-$OUT/flutter-3.24.5}"

export PATH="$HOME/.cargo/bin:$PATH"
# Xcode 27 SDK 를 CLT libclang 이 못 읽어 브리지가 깨진다(uint8_t → Pointer<Int>). CLT SDK 를 쓰게 한다.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export RUSTUP_TOOLCHAIN=1.75               # CI(taesan-android.yml)와 같은 Rust
export VCPKG_ROOT="$HOME/vcpkg-android"
export CARGO_TARGET_DIR="$OUT/target-android"
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" ANDROID_NDK="$ANDROID_NDK_HOME"
unset TAESAN_VARIANT TAESAN_INCOMING_PW_STORAGE TAESAN_INCOMING_PW_SALT TAESAN_RENDEZVOUS_SERVER TAESAN_RS_PUB_KEY
# macOS: bindgen(kcp-sys, scrap 등)이 Android 헤더를 찾도록 NDK sysroot 를 준다. Linux CI 는 호스트 /usr/include 로 넘어간다.
export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib
NDKSYS="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/sysroot"
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$NDKSYS"
export BINDGEN_EXTRA_CLANG_ARGS_armv7_linux_androideabi="--sysroot=$NDKSYS"

step() { echo "== $1 $(date +%T)"; }
die() { echo "FAIL: $1 (로그: $LOG)"; exit 1; }

# 중계 서버 주소·공개키(셸 해석 없이 한 줄씩 읽는다).
SRVF="$OUT/server.env"
[ -f "$SRVF" ] || die "$SRVF 가 없다(TAESAN_RENDEZVOUS_SERVER·TAESAN_RS_PUB_KEY)"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in TAESAN_RENDEZVOUS_SERVER=*|TAESAN_RS_PUB_KEY=*) export "${line%%=*}=${line#*=}" ;; esac
done < "$SRVF"
[ -n "${TAESAN_RENDEZVOUS_SERVER:-}" ] && [ -n "${TAESAN_RS_PUB_KEY:-}" ] || die "$SRVF 에 TAESAN_RENDEZVOUS_SERVER·TAESAN_RS_PUB_KEY 가 다 있어야 한다"
echo "relay server: $TAESAN_RENDEZVOUS_SERVER (key ${#TAESAN_RS_PUB_KEY} chars)"

# release: origin 에 있는 taesan-v* 태그·릴리즈 키·versionCode 를 빌드 전에 확인한다.
if [ "$TARGET" = release ]; then
  case "$BASE" in taesan-v*) ;; *) die "release 는 taesan-v* 태그만 받는다(받은 값: $BASE)" ;; esac
  rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE^{}" | awk '{print $1}')
  [ -n "$rc" ] || rc=$(git -C "$R" ls-remote origin "refs/tags/$BASE" | awk '{print $1}')
  lc=$(git -C "$R" rev-parse -q --verify "$BASE^{commit}")
  [ -n "$rc" ] && [ "$rc" = "$lc" ] || die "태그 $BASE 가 origin 에 없거나 로컬과 다르다(origin ${rc:-없음}, 로컬 ${lc:-없음})"
  [ -f "$KEYS/android-release.properties" ] && [ -s "$KEYS/android-release.sha256" ] || die "릴리즈 키가 없다($KEYS — make-android-release-key.sh)"
  case "${TAESAN_VERSION_CODE:-}" in ''|*[!0-9]*) die "TAESAN_VERSION_CODE(숫자)가 필요하다" ;; esac
  [ -x "$HOME/.cargo/bin/cargo-about" ] || die "cargo-about 이 없다(cargo install cargo-about --version 0.6.4 --locked)"
fi

# 0) worktree 를 새로 만든다(공용 작업 폴더와 분리).
step "worktree $BASE"
[ -d "$W" ] && git -C "$R" worktree remove --force "$W"
git -C "$R" worktree add --detach "$W" "$BASE" >/dev/null || die worktree
cd "$W" || die cd

# 앱용 Flutter 전용 복사본(처음 한 번): fvm/flutter-sdks 의 3.24.5 를 복사해 패치한다.
if [ ! -x "$FL_APP/bin/flutter" ]; then
  step "flutter 3.24.5 복사본"
  SRC_FL="$(fl 3.24.5)"
  [ -x "$SRC_FL/bin/flutter" ] || die "Flutter 3.24.5 가 없다(fvm install 3.24.5)"
  rsync -a "$SRC_FL/" "$FL_APP/" || die "Flutter 복사"
  git -C "$FL_APP" apply "$W/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff" || die "Flutter 패치"
fi

# 1) 브리지 생성(bridge.yml 재현: Flutter 3.22.3 + extended_text 13 임시 다운그레이드).
#    macOS: ffigen 에 CLT libclang 경로와 SDK sysroot 를 넘겨야 한다(값이 '-' 로 시작하므로 '=' 형식).
step bridge
SDK=$(xcrun --show-sdk-path)
sed -i '' -e 's/extended_text: 14.0.0/extended_text: 13.0.0/g' flutter/pubspec.yaml
( export PATH="$FL_BRIDGE/bin:$PATH"
  (cd flutter && flutter pub get) &&
  flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart \
    --c-output ./flutter/macos/Runner/bridge_generated.h \
    --llvm-path /Library/Developer/CommandLineTools/usr "--llvm-compiler-opts=-isysroot $SDK"
) > "$LOG/bridge.log" 2>&1 || die bridge
cp flutter/macos/Runner/bridge_generated.h flutter/ios/Runner/bridge_generated.h
git checkout -- flutter/pubspec.yaml flutter/pubspec.lock

# 2) 네이티브 라이브러리: CI 처럼 ABI 마다 의존성 → Rust 순서로 번갈아 한다(9dc8c7c). 다음 트리플렛 설치가 앞 설치분을 지우기 때문이다.
step deps-arm64; ./flutter/build_android_deps.sh arm64-v8a  > "$LOG/deps-arm64.log" 2>&1 || die deps-arm64
step rust-arm64; ./flutter/ndk_arm64.sh                      > "$LOG/rust-arm64.log" 2>&1 || die rust-arm64
# build_android_deps.sh 는 installed/arm-neon-android 를 arm-android 로 mv 한다. arm-android 가 이미 있으면 그 안에 중첩돼
# 다음 실행의 mv 가 "Directory not empty" 로 실패한다. 빌드는 arm-android/{include,lib} 만 쓰므로 중첩분을 지운다.
rm -rf "$VCPKG_ROOT/installed/arm-android/arm-neon-android"
step deps-armv7; ./flutter/build_android_deps.sh armeabi-v7a > "$LOG/deps-armv7.log" 2>&1 || die deps-armv7
step rust-armv7; ./flutter/ndk_arm.sh                        > "$LOG/rust-armv7.log" 2>&1 || die rust-armv7

# 3) APK(Flutter 3.24.5). macOS: libc++_shared 는 darwin-x86_64 경로에서 가져오고, Gradle 7.6.4 는 JDK 17 로 고정한다.
#    Flutter 가 JAVA_HOME 보다 Android Studio JBR(21)을 우선하므로 worktree 의 gradle.properties 로 지정한다(전역 flutter config 는 건드리지 않는다).
step apk
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
J=flutter/android/app/src/main/jniLibs; L="$NDKSYS/usr/lib"
mkdir -p "$J/arm64-v8a" "$J/armeabi-v7a"
cp "$L/aarch64-linux-android/libc++_shared.so" "$J/arm64-v8a/" || die "libc++ arm64"
cp "$L/arm-linux-androideabi/libc++_shared.so" "$J/armeabi-v7a/" || die "libc++ armv7"
cp "$CARGO_TARGET_DIR/aarch64-linux-android/release/liblibrustdesk.so" "$J/arm64-v8a/librustdesk.so" || die "arm64 .so"
cp "$CARGO_TARGET_DIR/armv7-linux-androideabi/release/liblibrustdesk.so" "$J/armeabi-v7a/librustdesk.so" || die "armv7 .so"
sed -i '' 's/org.gradle.jvmargs=-Xmx1024M/org.gradle.jvmargs=-Xmx2g/g' flutter/android/gradle.properties   # CI 와 같은 임시 수정
BUILD_NUMBER=()
if [ "$TARGET" = release ]; then
  cp "$KEYS/android-release.properties" flutter/android/key.properties || die "릴리즈 키 설정 복사"   # worktree 안(git 제외 파일)
  BUILD_NUMBER=(--build-number="$TAESAN_VERSION_CODE")
else
  sed -i '' 's/signingConfigs.release/signingConfigs.debug/g' flutter/android/app/build.gradle              # CI 와 같은 debug 서명
fi
echo "org.gradle.java.home=$JAVA_HOME" >> flutter/android/gradle.properties
( export PATH="$JAVA_HOME/bin:$FL_APP/bin:$PATH"
  cd flutter && flutter build apk --release --target-platform android-arm,android-arm64 "${BUILD_NUMBER[@]}"
) > "$LOG/apk.log" 2>&1 || die apk
rm -f flutter/android/key.properties   # release 에서 복사한 키 설정(그 밖 대상에는 없다)
VER=$(grep -E '^version:' flutter/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)
APK="$OUT/taesan-$VER-android-$TARGET.apk"
cp flutter/build/app/outputs/flutter-apk/app-release.apk "$APK" || die "APK 복사"

# 4) 확인: 정체·ABI·서명, ABI 마다 중계 서버 주소·키가 들어갔는지.
step verify
BT=$(ls -d "$HOME/Library/Android/sdk/build-tools/"* | tail -1)
BADGING=$("$BT/aapt2" dump badging "$APK")
echo "$BADGING" | grep -E "^package:|application-label:|native-code"
SIGNER=$("$BT/apksigner" verify --print-certs "$APK" | grep -E "Signer #1 certificate SHA-256" | awk '{print $NF}')
echo "Signer #1 certificate SHA-256: $SIGNER"
CHECK=""; BAD=""
for abi in arm64-v8a armeabi-v7a; do
  unzip -p "$APK" "lib/$abi/librustdesk.so" > "$LOG/check.so"
  srv=$(strings -a "$LOG/check.so" | grep -cF "$TAESAN_RENDEZVOUS_SERVER")
  key=$(strings -a "$LOG/check.so" | grep -cF "$TAESAN_RS_PUB_KEY")
  line="$abi server=$srv key=$key"
  echo "$line"; CHECK="${CHECK:+$CHECK; }$line"
  { [ "$srv" -ge 1 ] && [ "$key" -ge 1 ]; } || BAD=1
done
rm -f "$LOG/check.so"
[ -z "$BAD" ] || die "중계 서버 주소 확인 실패 — 이 APK 는 설치하지 않는다"
PKG_LINE=$(echo "$BADGING" | grep -E '^package:')
if [ "$TARGET" = release ]; then
  [ "$SIGNER" = "$(tr -d ' \n' < "$KEYS/android-release.sha256")" ] || die "서명 지문이 릴리즈 키와 다르다 — 이 APK 는 배포하지 않는다"
  echo "$PKG_LINE" | grep -q "name='com.taesan.remote'" || die "패키지가 com.taesan.remote 가 아니다"
  echo "$PKG_LINE" | grep -q "versionCode='$TAESAN_VERSION_CODE'" || die "versionCode 가 $TAESAN_VERSION_CODE 가 아니다"
fi
echo "done: $APK"

# 5) dist/<버전>-<sha9>-<대상>/ 에 대상 이름을 붙인 APK 와 manifest 를 모은다(build-windows-local.ps1 -Inno 와 같은 규칙).
step dist
COMMIT=$(git rev-parse HEAD)
DIST="$OUT/dist/$VER-${COMMIT[1,9]}-$TARGET"
mkdir -p "$DIST"
DAPK="$DIST/taesan-$VER-android-$TARGET.apk"
cp "$APK" "$DAPK" || die "dist 복사"
{
  echo "ref: $BASE ($COMMIT)"
  echo "platform: android (arm64-v8a, armeabi-v7a)"
  echo "target: $TARGET"
  echo "relay server: $TAESAN_RENDEZVOUS_SERVER"
  echo "check: $CHECK"
  echo "package: $(echo "$BADGING" | grep -E '^package:' | sed -E "s/.*name='([^']*)'.*versionCode='([^']*)'.*versionName='([^']*)'.*/\1 versionCode=\2 versionName=\3/")"
  echo "signer sha256: $SIGNER"
  [ "$TARGET" = release ] && echo "signing: release key ($KEYS/android-release.properties)"
  echo "apk: ${DAPK:t}"
  echo "size: $(stat -f %z "$DAPK")"
  echo "sha256: $(shasum -a 256 "$DAPK" | awk '{print $1}')"
  echo "built: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$DIST/manifest-android.txt"
# 6) release: 오픈소스 고지를 dist 에 둔다. APK 안의 Flutter NOTICES 와 vcpkg(arm-android — 마지막 ABI, 포트 구성은 두 ABI 가 같다).
if [ "$TARGET" = release ]; then
  step notices
  python3 res/taesan-build/collect-notices.py --platform android --out "$DIST/THIRD_PARTY_NOTICES-android.txt" --release "$BASE" \
    --flutter-notices "$DAPK" --vcpkg-share "$VCPKG_ROOT/installed/arm-android/share" --cargo-about "$HOME/.cargo/bin/cargo-about" \
    > "$LOG/notices-android.log" 2>&1 || die notices
  cp NOTICE "$DIST/NOTICE.txt" && cp LICENCE "$DIST/LICENCE.txt" || die "dist 고지 복사"
fi
echo "dist: $DAPK"
