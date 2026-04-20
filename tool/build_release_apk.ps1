# Release APK with Material icon tree-shaking (smaller glyph subset in AOT bundle).
# Usage (from repo root): pwsh -File tool/build_release_apk.ps1
# Optional: pass extra args after `--`. Avoid `--split-per-abi` together with `defaultConfig.ndk.abiFilters`
# in build.gradle.kts (AGP can report conflicting ABI configuration).

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$dartDefines = @()
if ($env:SUPABASE_URL) { $dartDefines += "--dart-define=SUPABASE_URL=$($env:SUPABASE_URL)" }
if ($env:SUPABASE_ANON_KEY) { $dartDefines += "--dart-define=SUPABASE_ANON_KEY=$($env:SUPABASE_ANON_KEY)" }

# Omit --target-platform so Flutter emits AOT for every ABI packaged by Gradle (arm32, arm64, x86_64).
$flutterArgs = @(
  "build", "apk",
  "--release",
  "--tree-shake-icons"
) + $dartDefines

Write-Host "flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
& flutter @flutterArgs
