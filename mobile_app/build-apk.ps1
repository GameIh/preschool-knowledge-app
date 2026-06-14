param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerIp,

    [ValidateRange(1, 65535)]
    [int]$Port = 8081,

    [ValidateSet('http', 'https')]
    [string]$Scheme = 'http',

    [ValidateSet('debug', 'profile', 'release')]
    [string]$Mode = 'release'
)

$hostType = [Uri]::CheckHostName($ServerIp)
if ($hostType -eq [UriHostNameType]::Unknown) {
    throw "Invalid server IP or hostname: $ServerIp"
}

$urlHost = if ($hostType -eq [UriHostNameType]::IPv6) {
    "[$ServerIp]"
} else {
    $ServerIp
}

$serverUrl = "${Scheme}://${urlHost}:${Port}"
$parsedUrl = $null

if (-not [Uri]::TryCreate($serverUrl, [UriKind]::Absolute, [ref]$parsedUrl) -or
    [string]::IsNullOrWhiteSpace($parsedUrl.Host)) {
    throw "Invalid server URL: $serverUrl"
}

Write-Host "Building APK for API: $serverUrl"

flutter build apk `
    "--$Mode" `
    "--dart-define=API_BASE_URL=$serverUrl"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "APK: $PSScriptRoot\build\app\outputs\flutter-apk\app-$Mode.apk"
