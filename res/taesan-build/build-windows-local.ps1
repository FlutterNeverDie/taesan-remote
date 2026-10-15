# 태산 원격지원 Windows x64 local build -> portable folder (+ optional Inno installer).
#
# Usage:  powershell -ExecutionPolicy Bypass -File res\taesan-build\build-windows-local.ps1 [-Ref <commit|branch|tag>]
#         [-Variant bidirectional|incoming] [-Target local|release] [-Inno]
#         (default ref: main, default variant: bidirectional, default target: local)
# Result: C:\taesan-build\taesan-<ver>-windows-<target>[-incoming]\ (unsigned portable folder, run taesan-remote.exe)
#         With -Inno also C:\taesan-build\dist\<ver>-<sha>-<target>\taesan-setup-<ver>-x86_64[-incoming]-<target>.exe
#         + manifest-<variant>.txt (needs Inno Setup 6)
# Logs:   C:\taesan-build\logs\windows-*.log
#
# Rules
# - Relay server: TAESAN_RENDEZVOUS_SERVER (host or host:port) and TAESAN_RS_PUB_KEY (hbbs id_ed25519.pub) come from
#   -ServerEnv (default C:\taesan-build\server.env, outside git). They are compiled in (option_env!).
# - Incoming-only variant: the shared password and salt come from -IncomingEnv (default C:\taesan-build\incoming.env:
#   TAESAN_INCOMING_PASSWORD=..., TAESAN_INCOMING_SALT=...; outside git). They are hashed with
#   res\taesan-variant\preset_hash.py; only the hash goes into the build. Values are never printed.
# - release: -Ref must be a taesan-v* tag that exists on origin with the same commit, and -Inno is required.
#   NOTICE.txt, LICENCE.txt and THIRD_PARTY_NOTICES.txt (res\taesan-build\collect-notices.py, needs cargo-about 0.6.4)
#   go into the installer payload. Unsigned.
# - The working folder is not touched: build in a fresh git worktree (wt-windows);
#   cargo target lives outside it (target-windows) and is linked in as a junction.
# - Short root (C:\taesan-build) because of MAX_PATH limits in vcpkg/cmake/flutter.
#
# Prerequisites (installed once, under C:\taesan-build\tools unless noted):
#   Visual Studio 2022 (MSVC, Windows SDK), rustup in %USERPROFILE%\.cargo (1.75 + rustfmt),
#   cargo-expand 1.0.95, flutter_rust_bridge_codegen 1.80.1 (--features uuid),
#   tools\flutter = Flutter 3.24.5 + rustdesk engine windows-x64-release, tools\llvm = LLVM 15.0.6,
#   tools\python = Python 3.12, vcpkg = microsoft/vcpkg (bootstrapped) in C:\taesan-build\vcpkg.
param(
  [string]$Ref = 'main',
  [string]$Client = (Join-Path $env:USERPROFILE 'Documents\GitHub\taesan-remote'),
  [string]$Out = 'C:\taesan-build',
  [ValidateSet('bidirectional', 'incoming')][string]$Variant = 'bidirectional',
  [ValidateSet('local', 'release')][string]$Target = 'local',
  [switch]$Inno,
  [string]$ServerEnv = 'C:\taesan-build\server.env',
  [string]$IncomingEnv = 'C:\taesan-build\incoming.env'
)
$Suffix = if ($Variant -eq 'incoming') { '-incoming' } else { '' }
$ErrorActionPreference = 'Continue'  # native tools write progress to stderr; exit codes are checked instead
$W = Join-Path $Out 'wt-windows'
$T = Join-Path $Out 'target-windows'
$LOG = Join-Path $Out 'logs'
$Tools = Join-Path $Out 'tools'
New-Item -ItemType Directory -Force $LOG, $T | Out-Null

$env:PATH = "$env:USERPROFILE\.cargo\bin;$Tools\flutter\bin;$Tools\python;$Tools\python\Scripts;$Tools\llvm\bin;$env:PATH"
$env:RUSTUP_TOOLCHAIN = '1.75'
$env:VCPKG_ROOT = Join-Path $Out 'vcpkg'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:VCPKG_DISABLE_METRICS = '1'
$env:LIBCLANG_PATH = "$Tools\llvm\bin"
foreach ($k in 'TAESAN_VARIANT', 'TAESAN_INCOMING_PW_STORAGE', 'TAESAN_INCOMING_PW_SALT', 'TAESAN_INCOMING_PASSWORD', 'TAESAN_INCOMING_SALT', 'TAESAN_RENDEZVOUS_SERVER', 'TAESAN_RS_PUB_KEY') {
  Remove-Item "Env:$k" -ErrorAction SilentlyContinue
}

function Step([string]$Name) { Write-Output "== $Name $(Get-Date -Format HH:mm:ss)" }
function Die([string]$Msg) { Write-Output "FAIL: $Msg (logs: $LOG)"; exit 1 }
# Run a command line through cmd so stderr goes to the log file instead of becoming PowerShell errors.
function Run([string]$Name, [string]$Cmd) {
  cmd /c "$Cmd >> `"$LOG\windows-$Name.log`" 2>&1"
  if ($LASTEXITCODE -ne 0) { Die "$Name (exit $LASTEXITCODE)" }
}
# KEY=VALUE lines -> environment (only the given keys).
function Load-Env([string]$File, [string[]]$Keys) {
  if (-not (Test-Path -LiteralPath $File)) { Die "$File not found ($($Keys -join ', '))" }
  foreach ($line in Get-Content -LiteralPath $File) {
    if ($line -match '^\s*([A-Z_]+)=(.*)$' -and $Keys -contains $Matches[1]) {
      Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2].Trim()
    }
  }
  foreach ($k in $Keys) { if (-not (Test-Path "Env:$k")) { Die "$k missing in $File" } }
}

# Relay server address and key.
Load-Env $ServerEnv @('TAESAN_RENDEZVOUS_SERVER', 'TAESAN_RS_PUB_KEY')
Write-Output "relay server: $env:TAESAN_RENDEZVOUS_SERVER (key $($env:TAESAN_RS_PUB_KEY.Length) chars)"

# release: a taesan-v* tag that exists on origin with the same commit, -Inno, cargo-about.
$CargoAbout = Join-Path $env:USERPROFILE '.cargo\bin\cargo-about.exe'
if ($Target -eq 'release') {
  if ($Ref -notlike 'taesan-v*') { Die "release takes only a taesan-v* tag (got $Ref)" }
  $rc = ((git -C $Client ls-remote origin "refs/tags/$Ref^{}") -split '\s+')[0]
  if (-not $rc) { $rc = ((git -C $Client ls-remote origin "refs/tags/$Ref") -split '\s+')[0] }
  $lc = git -C $Client rev-parse -q --verify "$Ref^{commit}"
  if (-not $rc -or $rc -ne $lc) { Die "tag $Ref is not on origin or differs from the local tag (origin '$rc', local '$lc') - git fetch --tags" }
  if (-not $Inno) { Die 'release needs -Inno' }
  if (-not (Test-Path -LiteralPath $CargoAbout)) { Die 'cargo-about not found (cargo install cargo-about --version 0.6.4 --locked)' }
}

# 0) Fresh worktree. Remove the target junction first so nothing follows it into the cargo cache.
Step "worktree $Ref"
if (Test-Path -LiteralPath $W) {
  $link = Get-Item -LiteralPath (Join-Path $W 'target') -Force -ErrorAction SilentlyContinue
  if ($link -and $link.LinkType) { $link.Delete() }
  git -C $Client worktree remove --force $W
  if (Test-Path -LiteralPath $W) { Die "could not remove old worktree $W" }
}
git -C $Client worktree add --detach $W $Ref
if ($LASTEXITCODE -ne 0) { Die worktree }
New-Item -ItemType Junction -Path (Join-Path $W 'target') -Target $T | Out-Null
Get-ChildItem $LOG -Filter 'windows-*.log' | Remove-Item

# Incoming-only variant: hash the shared password. The plain values live only in this block's environment.
if ($Variant -eq 'incoming') {
  Step "variant incoming"
  Load-Env $IncomingEnv @('TAESAN_INCOMING_PASSWORD', 'TAESAN_INCOMING_SALT')
  $env:PYTHONUTF8 = '1'
  $hashOut = python (Join-Path $W 'res\taesan-variant\preset_hash.py')
  $hashExit = $LASTEXITCODE
  Remove-Item Env:TAESAN_INCOMING_PASSWORD, Env:TAESAN_INCOMING_SALT -ErrorAction SilentlyContinue
  if ($hashExit -ne 0) { Die "password hash (preset_hash.py)" }
  foreach ($line in $hashOut) {
    $kv = $line.Split('=', 2)
    Set-Item -Path "Env:$($kv[0])" -Value $kv[1]
  }
  $env:TAESAN_VARIANT = 'incoming'
  python (Join-Path $W 'res\taesan-variant\apply_icons.py')
  if ($LASTEXITCODE -ne 0) { Die "incoming icons (apply_icons.py)" }
  # Fingerprint (first 5 hex of SHA-256 over the storage hash) to compare builds without showing the password.
  $h2 = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::ASCII.GetBytes($env:TAESAN_INCOMING_PW_STORAGE))
  $Fp = (($h2 | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 5)
  Write-Output "incoming password fingerprint $Fp"
}

# 1) Bridge (Flutter 3.24.5; ffigen gets libclang from tools\llvm).
Step bridge
Run bridge "cd /d `"$W\flutter`" && call flutter pub get"
Run bridge "cd /d `"$W`" && flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path `"$Tools\llvm`""
Copy-Item (Join-Path $W 'flutter\macos\Runner\bridge_generated.h') (Join-Path $W 'flutter\ios\Runner\bridge_generated.h')

# 2) vcpkg dependencies (x64-windows-static, manifest mode). Fast when already installed.
Step vcpkg
Run vcpkg "cd /d `"$W`" && `"$env:VCPKG_ROOT\vcpkg.exe`" install --triplet x64-windows-static --x-install-root=`"$env:VCPKG_ROOT\installed`""

# 3) Build.
Step build
Run build "cd /d `"$W`" && python build.py --portable --flutter --skip-portable-pack --hwcodec --vram"

# 4) Copy the portable folder out of the worktree.
Step copy
$ver = ((Select-String -Path (Join-Path $W 'flutter\pubspec.yaml') -Pattern '^version:').Line -split '\s+')[1].Split('+')[0]
$src = Join-Path $W 'flutter\build\windows\x64\runner\Release'
$dest = Join-Path $Out "taesan-$ver-windows-$Target$Suffix"
if (-not (Test-Path -LiteralPath (Join-Path $src 'taesan-remote.exe'))) { Die "taesan-remote.exe not found in $src" }
if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force -LiteralPath $dest }
Copy-Item -Recurse -LiteralPath $src -Destination $dest

# 5) Verify: the relay server address and key are compiled in. Do not run the app if this fails.
Step verify
$counts = python -c "import sys;d=open(sys.argv[1],'rb').read();print(*[d.count(x.encode()) for x in sys.argv[2:]])" (Join-Path $dest 'librustdesk.dll') $env:TAESAN_RENDEZVOUS_SERVER $env:TAESAN_RS_PUB_KEY
$srv, $key = $counts -split ' ' | ForEach-Object { [int]$_ }
$Check = "server=$srv key=$key"
Write-Output $Check
if ($srv -lt 1 -or $key -lt 1) { Die "relay server or key is not in the build - do not run this build" }
Write-Output "done: $dest\taesan-remote.exe"

# 6) Optional Inno installer. Same AppId for both variants.
if ($Inno) {
  Step inno
  $iscc = @((Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'), (Join-Path $Tools 'inno\ISCC.exe')) |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $iscc) { Die "ISCC.exe not found (install Inno Setup 6 or put it in $Tools\inno)" }
  $issDir = Join-Path $W 'res\inno'
  Copy-Item -Recurse -LiteralPath $dest -Destination (Join-Path $issDir 'rustdesk')
  $payload = Join-Path $issDir 'rustdesk'
  Copy-Item -LiteralPath (Join-Path $W 'NOTICE') -Destination (Join-Path $payload 'NOTICE.txt')
  Copy-Item -LiteralPath (Join-Path $W 'LICENCE') -Destination (Join-Path $payload 'LICENCE.txt')
  if ($Target -eq 'release') {
    Step notices
    $Notices = Join-Path $LOG 'THIRD_PARTY_NOTICES-windows-x64.txt'
    $env:PYTHONUTF8 = '1'
    Run notices "cd /d `"$W`" && python res\taesan-build\collect-notices.py --platform windows-x64 --out `"$Notices`" --release $Ref --flutter-notices `"$dest\data\flutter_assets\NOTICES.Z`" --vcpkg-share `"$env:VCPKG_ROOT\installed\x64-windows-static\share`" --cargo-about `"$CargoAbout`""
    Copy-Item -LiteralPath $Notices -Destination (Join-Path $payload 'THIRD_PARTY_NOTICES.txt')
  }
  $defs = "/DMyAppVersion=$ver"
  if ($Suffix) { $defs += " /DMyVariantSuffix=$Suffix" }
  Run inno "cd /d `"$issDir`" && `"$iscc`" $defs taesan.iss"
  $setup = Get-ChildItem -LiteralPath $issDir -Recurse -Filter 'taesan-setup-*.exe' | Select-Object -First 1
  if (-not $setup) { Die "installer not found under $issDir" }
  # Collect into dist\<ver>-<sha>-<target>\ with the target in the name, so test installers are not mistaken for releases.
  $commit = git -C $W rev-parse HEAD
  $dist = Join-Path $Out "dist\$ver-$($commit.Substring(0, 9))-$Target"
  New-Item -ItemType Directory -Force $dist | Out-Null
  $installer = Join-Path $dist "$($setup.BaseName)-$Target$($setup.Extension)"
  Copy-Item -LiteralPath $setup.FullName -Destination $installer -Force
  $file = Get-Item -LiteralPath $installer
  $manifest = @(
    "ref: $Ref ($commit)",
    "variant: $Variant",
    "target: $Target",
    "relay server: $env:TAESAN_RENDEZVOUS_SERVER",
    "check: $Check",
    "signature: unsigned"
  )
  if ($Variant -eq 'incoming') { $manifest += "incoming password fingerprint: $Fp" }
  $manifest += @(
    "installer: $($file.Name)",
    "size: $($file.Length)",
    "sha256: $((Get-FileHash -Algorithm SHA256 -LiteralPath $installer).Hash.ToLower())",
    "built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  )
  [System.IO.File]::WriteAllLines((Join-Path $dist "manifest-$Variant.txt"), $manifest, (New-Object System.Text.UTF8Encoding $false))
  Write-Output "installer: $installer"
}
