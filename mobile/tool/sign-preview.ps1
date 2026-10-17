param(
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$Output,
    [Parameter(Mandatory)][string]$ToolsDirectory,
    [Parameter(Mandatory)][string]$JavaDirectory,
    [Parameter(Mandatory)][string]$Keystore,
    [Parameter(Mandatory)][string]$KeyAlias
)
$ErrorActionPreference = 'Stop'
if (!$env:POSEY_SIGN_PASSWORD) { throw 'Set POSEY_SIGN_PASSWORD in the current process environment.' }
$inputApk = (Resolve-Path -LiteralPath $Apk).Path
$outputApk = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputApk) { throw 'Output already exists; choose a new file name.' }
$toolsRoot = (Resolve-Path -LiteralPath $ToolsDirectory).Path
$keyPath = (Resolve-Path -LiteralPath $Keystore).Path
$packageInfo = & (Join-Path $toolsRoot 'aapt2.exe') dump badging $inputApk 2>&1
if ($LASTEXITCODE -ne 0 -or ($packageInfo -join "`n") -notmatch "package: name='com.posey.camera.preview'") { throw 'Input is not the Posey preview package.' }
$folder = Split-Path -Parent $outputApk
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$aligned = Join-Path $folder ('.aligned-' + [guid]::NewGuid().ToString() + '.apk')
$previousJava = $env:JAVA_HOME
try {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JavaDirectory).Path
    & (Join-Path $toolsRoot 'zipalign.exe') -P 16 4 $inputApk $aligned
    if ($LASTEXITCODE -ne 0) { throw 'APK alignment failed.' }
    & (Join-Path $toolsRoot 'apksigner.bat') sign --ks $keyPath --ks-key-alias $KeyAlias --ks-pass env:POSEY_SIGN_PASSWORD --key-pass env:POSEY_SIGN_PASSWORD --out $outputApk $aligned
    if ($LASTEXITCODE -ne 0) { throw 'APK signing failed.' }
    & (Join-Path $toolsRoot 'apksigner.bat') verify --verbose --print-certs $outputApk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
    & (Join-Path $toolsRoot 'zipalign.exe') -c -P 16 4 $outputApk
    if ($LASTEXITCODE -ne 0) { throw 'Signed APK alignment verification failed.' }
    Get-FileHash -LiteralPath $outputApk -Algorithm SHA256
} finally {
    $env:JAVA_HOME = $previousJava
    if (Test-Path -LiteralPath $aligned) { Remove-Item -LiteralPath $aligned }
}
