param(
    [string]$PythonExe = (Join-Path $PSScriptRoot '.venv/Scripts/python.exe'),
    [string]$SourceApp = (Join-Path $PSScriptRoot 'app.py'),
    [string]$DeployDirectory = (Join-Path $env:LOCALAPPDATA 'Jenkins/lab4-deploy/myflaskapp'),
    [ValidateRange(1024, 65535)][int]$Port = 5000
)

$ErrorActionPreference = 'Stop'
$python = (Resolve-Path -LiteralPath $PythonExe).Path
$source = (Resolve-Path -LiteralPath $SourceApp).Path
$deployRoot = [IO.Path]::GetFullPath($DeployDirectory)
$url = "http://127.0.0.1:$Port/"

# Only stop this virtual environment's Flask server with these exact arguments.
# Never kill an unrelated Python process or a process merely for using the port.
$serverPattern = '^\s*"?' + [regex]::Escape($python) + '"?\s+-m\s+flask\s+run\s+--host=127\.0\.0\.1\s+--port=' + $Port + '\s+--no-reload\s*$'
$childPattern = '\s+-m\s+flask\s+run\s+--host=127\.0\.0\.1\s+--port=' + $Port + '\s+--no-reload\s*$'
function Get-LabServers {
    $pythonProcesses = @(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'")
    $launchers = @($pythonProcesses | Where-Object { $_.CommandLine -match $serverPattern })
    # The Windows venv launcher runs the base interpreter as a direct child.
    $children = @($pythonProcesses | Where-Object {
        $_.ParentProcessId -in $launchers.ProcessId -and $_.CommandLine -match $childPattern
    })
    # Stop children first; otherwise a base interpreter can remain listening.
    return @($children) + @($launchers)
}
$oldServers = @(Get-LabServers)
foreach ($oldServer in $oldServers) {
    Stop-Process -Id $oldServer.ProcessId -ErrorAction SilentlyContinue
}
if ($oldServers.Count -gt 0) { Start-Sleep -Seconds 2 }

$listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -gt 0) {
    throw "Port $Port is occupied. The other program was NOT stopped."
}

New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
$destination = Join-Path $deployRoot 'app.py'
if (Test-Path -LiteralPath $destination) {
    Copy-Item -LiteralPath $destination -Destination (Join-Path $deployRoot 'app.previous.py') -Force
}
Copy-Item -LiteralPath $source -Destination $destination -Force

$env:FLASK_APP = 'app:app'
$env:FLASK_DEBUG = '0'
$env:FLASK_ENV = 'production'
$env:JENKINS_NODE_COOKIE = 'myflaskapp-lab4-server'
$stdoutLog = Join-Path $deployRoot 'server.out.log'
$stderrLog = Join-Path $deployRoot 'server.err.log'
$server = Start-Process -FilePath $python -ArgumentList @(
    '-m', 'flask', 'run', '--host=127.0.0.1', "--port=$Port", '--no-reload'
) -WorkingDirectory $deployRoot -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog

for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Seconds 1
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
    } catch {
        $response = $null
    }
    if ($null -ne $response -and $response.StatusCode -eq 200 -and
        $response.Content -ceq 'Hello, CI/CD with Jenkins!') {
        $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)
        $liveServers = @(Get-LabServers)
        $ownedListener = @($listeners | Where-Object { $_.OwningProcess -in $liveServers.ProcessId })
        if ($ownedListener.Count -eq 0) {
            Write-Output 'The response was not served by this deployment.'
            break
        }
        Write-Output "Deployed successfully: $url"
        Write-Output "Server PID: $($ownedListener[0].OwningProcess)"
        Write-Output "Deployment directory: $deployRoot"
        exit 0
    }
}

if (Test-Path -LiteralPath $stderrLog) {
    Get-Content -LiteralPath $stderrLog -Tail 20
}
$failedServers = @(Get-LabServers)
foreach ($failedServer in $failedServers) {
    Stop-Process -Id $failedServer.ProcessId -ErrorAction SilentlyContinue
}
throw "The application did not pass its health check at $url."
