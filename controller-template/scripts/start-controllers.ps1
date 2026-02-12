[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 10000)]
    [int]$Count,

    [ValidateRange(1, 10000)]
    [int]$StartIndex = 1,

    [string]$ProjectPrefix = "ctrl",
    [string]$ControllerIdPrefix = "ctrl",
    [string]$City = "moscow",
    [string]$TelemetryTopic = "telemetry.v1",
    [string]$CommandTopic = "command.v1",
    [string]$KafkaBootstrapServers = "host.docker.internal:29092",
    [int]$SendIntervalSec = 5,
    [int]$BaseWatts = 120,
    [int]$NoiseWatts = 30,
    [int]$NetemDelayMs = 0,
    [int]$NetemJitterMs = 0,
    [double]$NetemLossPct = 0,
    [switch]$Build
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateDir = Split-Path -Parent $scriptsDir
$composeFile = Join-Path $templateDir "docker-compose.yaml"
$envDir = Join-Path $templateDir ".generated-env"

if (-not (Test-Path $composeFile)) {
    throw "Compose file was not found: $composeFile"
}

New-Item -ItemType Directory -Path $envDir -Force | Out-Null

for ($offset = 0; $offset -lt $Count; $offset++) {
    $index = $StartIndex + $offset
    $projectName = ("{0}_{1:D4}" -f $ProjectPrefix, $index).ToLowerInvariant()
    $controllerId = "{0}-{1:D4}" -f $ControllerIdPrefix, $index
    $envFile = Join-Path $envDir "$projectName.env"

    $envContent = @(
        "CONTROLLER_ID=$controllerId"
        "CITY=$City"
        "TELEMETRY_TOPIC=$TelemetryTopic"
        "COMMAND_TOPIC=$CommandTopic"
        "KAFKA_BOOTSTRAP_SERVERS=$KafkaBootstrapServers"
        "SEND_INTERVAL_SEC=$SendIntervalSec"
        "BASE_WATTS=$BaseWatts"
        "NOISE_WATTS=$NoiseWatts"
        "NETEM_DELAY_MS=$NetemDelayMs"
        "NETEM_JITTER_MS=$NetemJitterMs"
        "NETEM_LOSS_PCT=$NetemLossPct"
    )

    Set-Content -Path $envFile -Value $envContent -Encoding Ascii

    $args = @(
        "compose"
        "-f", $composeFile
        "--project-name", $projectName
        "--env-file", $envFile
        "up", "-d"
    )
    if ($Build) {
        $args += "--build"
    }

    & docker @args
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start controller project '$projectName'"
    }

    Write-Host "[started] project=$projectName controller_id=$controllerId env_file=$envFile"
}

