[CmdletBinding()]
param(
    [string]$ProjectPrefix = "",
    [switch]$RemoveVolumes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$templateDir = Split-Path -Parent $scriptsDir
$composeFile = Join-Path $templateDir "docker-compose.yaml"

if (-not (Test-Path $composeFile)) {
    throw "Compose file was not found: $composeFile"
}

$controllerIds = @(
    & docker ps -a --filter "label=com.docker.compose.service=controller" --format "{{.ID}}"
)
if ($LASTEXITCODE -ne 0) {
    throw "Failed to query docker controller containers"
}

if ((@($controllerIds)).Count -eq 0) {
    Write-Host "No controller containers were found."
    return
}

$inspect = & docker inspect $controllerIds | ConvertFrom-Json
$projects = @(
    $inspect |
        ForEach-Object { $_.Config.Labels."com.docker.compose.project" } |
        Where-Object { $_ -and $_.Trim().Length -gt 0 } |
        Sort-Object -Unique
)

if ($ProjectPrefix -and $ProjectPrefix.Trim().Length -gt 0) {
    $prefix = $ProjectPrefix.ToLowerInvariant()
    $projects = @($projects | Where-Object { $_.ToLowerInvariant().StartsWith($prefix) })
}

if ((@($projects)).Count -eq 0) {
    Write-Host "No matching controller projects were found."
    return
}

foreach ($project in $projects) {
    $args = @(
        "compose"
        "-f", $composeFile
        "--project-name", $project
        "down"
        "--remove-orphans"
    )
    if ($RemoveVolumes) {
        $args += "-v"
    }

    & docker @args
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to stop project '$project'"
        continue
    }

    Write-Host "[stopped] project=$project"
}
