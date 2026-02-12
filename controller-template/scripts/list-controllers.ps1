[CmdletBinding()]
param(
    [string]$ProjectPrefix = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$controllerIds = @(
    & docker ps --filter "label=com.docker.compose.service=controller" --format "{{.ID}}"
)
if ($LASTEXITCODE -ne 0) {
    throw "Failed to query running controller containers"
}

if ((@($controllerIds)).Count -eq 0) {
    Write-Host "No running controller containers were found."
    return
}

$inspect = & docker inspect $controllerIds | ConvertFrom-Json
$rows = foreach ($item in $inspect) {
    $envMap = @{}
    foreach ($entry in $item.Config.Env) {
        $pair = $entry.Split("=", 2)
        if ($pair.Count -eq 2) {
            $envMap[$pair[0]] = $pair[1]
        }
    }

    [PSCustomObject]@{
        Project      = $item.Config.Labels."com.docker.compose.project"
        Container    = $item.Name.TrimStart("/")
        ControllerId = $envMap["CONTROLLER_ID"]
        City         = $envMap["CITY"]
        Status       = $item.State.Status
    }
}

if ($ProjectPrefix -and $ProjectPrefix.Trim().Length -gt 0) {
    $prefix = $ProjectPrefix.ToLowerInvariant()
    $rows = @($rows | Where-Object { $_.Project.ToLowerInvariant().StartsWith($prefix) })
}

if ((@($rows)).Count -eq 0) {
    Write-Host "No running controller containers match the requested filter."
    return
}

$rows |
    Sort-Object Project, Container |
    Format-Table -AutoSize
