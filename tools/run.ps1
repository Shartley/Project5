param(
    [ValidateSet('Desktop', 'XR', 'SimulatedXR', 'Tests', 'VisualTests', 'QuestCheck', 'QuestExport', 'WebExport')]
    [string]$Mode = 'Desktop',
    [string]$GodotExe = $env:GODOT_BIN
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $GodotExe) {
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { $GodotExe = $command.Source; break }
    }
}
if (-not $GodotExe) {
    $candidate = Join-Path $env:USERPROFILE 'Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
    if (Test-Path -LiteralPath $candidate) { $GodotExe = $candidate }
}
if (-not $GodotExe -or -not (Test-Path -LiteralPath $GodotExe)) {
    throw 'Godot not found. Supply -GodotExe with the path to Godot 4.7.2, or set GODOT_BIN.'
}
$logPath = Join-Path $projectRoot '.godot/rocky-run.log'
New-Item -ItemType Directory -Path (Join-Path $projectRoot '.godot') -Force | Out-Null
$launchArgs = @('--path', $projectRoot, '--log-file', $logPath)
if ($Mode -in @('QuestCheck', 'QuestExport')) {
    $missing = [System.Collections.Generic.List[string]]::new()
    $templateDir = Join-Path $env:APPDATA 'Godot/export_templates/4.7.2.stable'
    if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'android_debug.apk'))) {
        $missing.Add('Godot 4.7.2 Android export templates (Editor > Manage Export Templates)')
    }
    $sdkPath = $env:ANDROID_HOME
    if (-not $sdkPath) { $sdkPath = $env:ANDROID_SDK_ROOT }
    if (-not $sdkPath) { $sdkPath = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    $adbPath = Join-Path $sdkPath 'platform-tools/adb.exe'
    if (-not (Test-Path -LiteralPath $adbPath)) { $missing.Add('Android SDK: set ANDROID_HOME and configure Godot Editor Settings > Export > Android') }
    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if (-not $javaCommand -and -not ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin/java.exe')))) {
        $missing.Add('OpenJDK 17: configure JAVA_HOME and Godot Editor Settings > Export > Android')
    }
    if ($missing.Count -gt 0) {
        Write-Output 'Quest prerequisites missing:'
        foreach ($item in $missing) { Write-Output "- $item" }
        exit 2
    }
    if ($Mode -eq 'QuestCheck') {
        & $adbPath devices
        Write-Output 'Prerequisites found. Confirm the headset appears as device (authorized), not unauthorized.'
        exit $LASTEXITCODE
    }
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'exports') -Force | Out-Null
    $launchArgs += @('--headless', '--xr-mode', 'off', '--export-debug', 'Quest Debug', (Join-Path $projectRoot 'exports/awakening-quest.apk'))
} else {
    switch ($Mode) {
        'WebExport' {
            New-Item -ItemType Directory -Path (Join-Path $projectRoot 'exports/web') -Force | Out-Null
            $launchArgs += @('--headless', '--xr-mode', 'off', '--export-debug', 'Web', (Join-Path $projectRoot 'exports/web/index.html'))
        }
        'XR' { $launchArgs += @('--xr-mode', 'on', '--', '--xr') }
        'SimulatedXR' { $launchArgs += @('--xr-mode', 'off', '--', '--simulate-xr') }
        'Tests' { $launchArgs += @('--headless', '--xr-mode', 'off', '--script', 'res://tests/run_tests.gd') }
        'VisualTests' { $launchArgs += @('--xr-mode', 'off', '--script', 'res://tests/visual_playtest.gd') }
        default { $launchArgs += @('--xr-mode', 'off') }
    }
}
& $GodotExe @launchArgs
$exitCode = $LASTEXITCODE
if ($Mode -in @('Tests', 'VisualTests')) {
    $logText = Get-Content -LiteralPath $logPath -Raw
    if ($logText -match 'SCRIPT ERROR:|FAIL:|Failed to load') { $exitCode = 1 }
    $marker = if ($Mode -eq 'Tests') { 'ROCKY TESTS:' } else { 'VISUAL PLAYTEST:' }
    if (-not $logText.Contains($marker)) { $exitCode = 1 }
}
exit $exitCode
