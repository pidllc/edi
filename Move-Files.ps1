param(
    [Parameter(Mandatory=$true)]
    [string]$Source,

    [Parameter(Mandatory=$true)]
    [string]$Destination
)

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Write-Host "Created: $Destination"
}

$files = Get-ChildItem -Path $Source -File
if (-not $files) {
    Write-Host "No files found matching: $Source"
    return
}

Write-Host "Found $($files.Count) file(s). Moving to $Destination ..."
$files | Move-Item -Destination $Destination -Force
Write-Host "Done."