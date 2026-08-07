[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SN,

    [string]$LogsRoot = "C:\Users\User\Desktop\logs",
    [string]$LogSubdirectory = "",
    [string]$RobocalRoot = "C:\Users\User\Robocal-v4",
    [string]$Template,
    [string]$OutputName = "ML_Robocal.csv",
    [string]$IntermediateName = "ML_Robocal_generated.csv",
    [string]$Run,
    [switch]$OfficialOnly,
    [switch]$OverwriteTemplate
)

$ErrorActionPreference = "Stop"
if (-not $Template) {
    $Template = Join-Path $PSScriptRoot "ML_Robocal.csv"
}
$snPath = Join-Path $LogsRoot $SN
$logPath = if ($LogSubdirectory) { Join-Path $snPath $LogSubdirectory } else { $snPath }
$reportTool = Join-Path $PSScriptRoot "robocal_report.py"
$adapterTool = Join-Path $PSScriptRoot "robocal_ml_adapter.py"
$intermediatePath = if ($OverwriteTemplate) {
    Join-Path ([System.IO.Path]::GetTempPath()) ("ML_Robocal_{0}_{1}.csv" -f $SN, [guid]::NewGuid())
} else {
    Join-Path $logPath $IntermediateName
}
$outputPath = if ($OverwriteTemplate) { $Template } else { Join-Path $logPath $OutputName }

foreach ($requiredPath in @($logPath, $reportTool, $adapterTool, $Template)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required path not found: $requiredPath"
    }
}

$reportArguments = @(
    "-3.11",
    $reportTool,
    $logPath,
    "--robocal-root",
    $RobocalRoot,
    "--output",
    $intermediatePath
)
if ($Run) {
    $reportArguments += @("--run", $Run)
}
if ($OfficialOnly) {
    $reportArguments += "--official-only"
}

try {
    Write-Host "Generating RoboCal report for SN: $SN"
    & py @reportArguments
    if ($LASTEXITCODE -ne 0) {
        throw "robocal_report.py failed with exit code $LASTEXITCODE"
    }

    $adapterArguments = @(
        "-3.11",
        $adapterTool,
        $intermediatePath,
        "--template",
        $Template,
        "--output",
        $outputPath,
        "--serial-number",
        $SN
    )
    if ($OverwriteTemplate) {
        $adapterArguments += "--replace-tests"
    }
    & py @adapterArguments
    if ($LASTEXITCODE -ne 0) {
        throw "robocal_ml_adapter.py failed with exit code $LASTEXITCODE"
    }
} finally {
    if ($OverwriteTemplate -and (Test-Path -LiteralPath $intermediatePath)) {
        Remove-Item -LiteralPath $intermediatePath -Force
    }
}

Write-Host "Generated ML report: $outputPath"