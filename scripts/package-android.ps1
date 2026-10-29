param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$JavaDirectory = $env:JAVA_HOME,
    [string]$GradleCommand
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
if (-not $JavaDirectory) { $JavaDirectory = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr' }
if (-not (Test-Path (Join-Path $AndroidSdk 'platforms\android-35\android.jar'))) { throw 'Install Android SDK Platform 35, then pass -AndroidSdk with its SDK directory.' }
if (-not (Test-Path (Join-Path $JavaDirectory 'bin\java.exe'))) { throw 'Pass -JavaDirectory with a JDK 17 or later.' }
if (-not $GradleCommand) { $GradleCommand = Join-Path $projectRoot 'clients\android\gradlew.bat' }
$signingDirectory = Join-Path $projectRoot '.local\android-signing'
$keystore = Join-Path $signingDirectory 'release.p12'
$signingConfig = Join-Path $signingDirectory 'signing.json'
$originalJava = $env:JAVA_HOME
$originalSdk = $env:ANDROID_HOME
$originalStore = $env:SPELUNKR_KEYSTORE_FILE
$originalPassword = $env:SPELUNKR_STORE_PASSWORD
try {
    $env:JAVA_HOME = $JavaDirectory
    $env:ANDROID_HOME = $AndroidSdk
    if (Test-Path $keystore) {
        if (-not (Test-Path $signingConfig)) { throw 'The signing keystore exists, but signing.json is missing. Restore its signing settings to build compatible updates.' }
        $settings = Get-Content -LiteralPath $signingConfig -Raw | ConvertFrom-Json
        $env:SPELUNKR_STORE_PASSWORD = $settings.password
    } else {
        New-Item -ItemType Directory -Path $signingDirectory -Force | Out-Null
        $randomBytes = New-Object byte[] 32
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $generator.GetBytes($randomBytes)
        $generator.Dispose()
        $env:SPELUNKR_STORE_PASSWORD = [Convert]::ToBase64String($randomBytes)
        & (Join-Path $JavaDirectory 'bin\keytool.exe') -genkeypair -keystore $keystore -storetype PKCS12 -alias spelunkr -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Spelunkr Guide local build' -storepass:env SPELUNKR_STORE_PASSWORD -keypass:env SPELUNKR_STORE_PASSWORD -noprompt
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the local APK signing key.' }
        @{ password = $env:SPELUNKR_STORE_PASSWORD } | ConvertTo-Json | Set-Content -LiteralPath $signingConfig -Encoding UTF8
    }
    $env:SPELUNKR_KEYSTORE_FILE = $keystore
    & $GradleCommand -p (Join-Path $projectRoot 'clients\android') assembleRelease lintRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android build or lint failed.' }
    $distribution = Join-Path $projectRoot 'dist'
    New-Item -ItemType Directory -Path $distribution -Force | Out-Null
    $apk = Join-Path $distribution 'spelunkr-guide-android.apk'
    Copy-Item -LiteralPath (Join-Path $projectRoot 'clients\android\app\build\outputs\apk\release\app-release.apk') -Destination $apk -Force
    Write-Output "Built $apk"
} finally {
    $env:JAVA_HOME = $originalJava
    $env:ANDROID_HOME = $originalSdk
    $env:SPELUNKR_KEYSTORE_FILE = $originalStore
    $env:SPELUNKR_STORE_PASSWORD = $originalPassword
}
