# Starts the loopback-only local API if needed, then runs the outbound bridge.
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ExpectedRoot = Join-Path $HOME "pi-control"
if (-not (Test-Path $ExpectedRoot) -or $RepoRoot -ne (Resolve-Path $ExpectedRoot).Path) {
    throw "Bitte das Projekt zuerst nach $ExpectedRoot legen. Gefunden: $RepoRoot"
}
$PythonCommand = Get-Command python -ErrorAction SilentlyContinue
if (-not $PythonCommand) { throw "Python wurde nicht gefunden." }
$DefaultServerUrl = "https://shape-squeegee-unblended.ngrok-free.dev"
$EnteredUrl = Read-Host "Pi-Control HTTPS-URL [$DefaultServerUrl]"
$env:PI_CONTROL_SERVER_URL = if ([string]::IsNullOrWhiteSpace($EnteredUrl)) { $DefaultServerUrl } else { $EnteredUrl.Trim() }
if (-not $env:PI_CONTROL_SERVER_URL.StartsWith("https://")) { throw "Aus Sicherheitsgründen wird nur HTTPS akzeptiert." }

$SecureToken = Read-Host "Gemeinsames PC-Agent-Token (Eingabe ist verborgen)" -AsSecureString
$BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
try { $env:PI_CONTROL_PC_AGENT_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }
if ($env:PI_CONTROL_PC_AGENT_TOKEN.Length -lt 40) { throw "Das Token ist zu kurz; mindestens 40 Zeichen verwenden." }

$AgentDirectory = Join-Path $HOME ".pi-control-agent"
New-Item -ItemType Directory -Force -Path $AgentDirectory | Out-Null
$StatusCode = 0
try {
    $null = Invoke-WebRequest -Uri "http://127.0.0.1:8765/v1/status" -TimeoutSec 1 -UseBasicParsing
    $StatusCode = 200
} catch {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { $StatusCode = 401 }
}
if ($StatusCode -ne 200 -and $StatusCode -ne 401) {
    $ApiScript = Join-Path $PSScriptRoot "local_api.py"
    $Arguments = '-u "{0}" --workspace "{1}" --access-root "{2}"' -f $ApiScript, $RepoRoot, $HOME
    Start-Process -FilePath $PythonCommand.Source -ArgumentList $Arguments -WorkingDirectory $RepoRoot -WindowStyle Hidden | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        try {
            $null = Invoke-WebRequest -Uri "http://127.0.0.1:8765/v1/status" -TimeoutSec 1 -UseBasicParsing
            $StatusCode = 200
        } catch {
            if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { $StatusCode = 401 }
        }
        if ($StatusCode -eq 200 -or $StatusCode -eq 401) { break }
    }
}
if ($StatusCode -ne 200 -and $StatusCode -ne 401) { throw "Lokale API konnte nicht gestartet werden. Logdatei: $AgentDirectory\local-api.log" }
Write-Host "Lokale API bereit. Erlaubt sind ausschließlich Datei-Auflisten und Datei-Lesen im pi-control-Projekt."
& $PythonCommand.Source (Join-Path $PSScriptRoot "bridge_client.py")
