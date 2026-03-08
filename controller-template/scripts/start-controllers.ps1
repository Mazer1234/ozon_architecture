[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 10000)]
    [int]$Count,

    [ValidateRange(1, 10000)]
    [int]$StartIndex = 1,

    [string]$ProjectPrefix = "ctrl",
    [string]$ControllerIdPrefix = "ctrl",
    [string]$City = "random",
    [string[]]$Cities = @("moscow", "spb", "kazan", "ekb", "novgorod", "perm", "rostov", "sochi"),
    [string]$TelemetryTopic = "telemetry.v1",
    [string]$CommandTopic = "command.v1",
    [string]$KafkaBootstrapServers = "host.docker.internal:29092",
    [string]$KafkaProducerAcks = "all",
    [string]$KafkaProducerEnableIdempotence = "true",
    [ValidateRange(1, 1000)]
    [int]$KafkaProducerRetries = 5,
    [ValidateRange(1, 60000)]
    [int]$KafkaProducerRetryBackoffMs = 100,
    [ValidateRange(1000, 600000)]
    [int]$KafkaProducerRequestTimeoutMs = 30000,
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
$composeDevFile = Join-Path $templateDir "docker-compose.dev.yaml"
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
    $cityForController = $City
    if ([string]::IsNullOrWhiteSpace($City) -or $City -in @("random", "__RANDOM__")) {
        $cityForController = Get-Random -InputObject $Cities
    }

    $envContent = @(
        "CONTROLLER_ID=$controllerId"
        "CITY=$cityForController"
        "TELEMETRY_TOPIC=$TelemetryTopic"
        "COMMAND_TOPIC=$CommandTopic"
        "KAFKA_BOOTSTRAP_SERVERS=$KafkaBootstrapServers"
        "KAFKA_PRODUCER_ACKS=$KafkaProducerAcks"
        "KAFKA_PRODUCER_ENABLE_IDEMPOTENCE=$KafkaProducerEnableIdempotence"
        "KAFKA_PRODUCER_RETRIES=$KafkaProducerRetries"
        "KAFKA_PRODUCER_RETRY_BACKOFF_MS=$KafkaProducerRetryBackoffMs"
        "KAFKA_PRODUCER_REQUEST_TIMEOUT_MS=$KafkaProducerRequestTimeoutMs"
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
        "-f", $composeDevFile
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

