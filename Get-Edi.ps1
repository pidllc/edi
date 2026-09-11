param(
    [Parameter(Mandatory=$true)]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$Source,

    [Parameter(Mandatory=$false)]
    [string]$Destination

)

if ($Action -eq "check997") {
    & python $PSScriptRoot\edi997_check.py "Z:\ISOFT\inbox\walmart\*997*.in"
} 
elseif ($Action -eq "analyze850") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    & python $PSScriptRoot\edi850_analyze.py "Z:\ISOFT\inbox\walmart\${DATETIME}*.in"
}
elseif ($Action -eq "analyze850andrew") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    & python $PSScriptRoot\edi850_analyze.py "Z:\ISOFT\inbox\walmart\*andrew*.in"
}
elseif ($Action -eq "detail850") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    & python $PSScriptRoot\edi850_podetails.py "Z:\ISOFT\inbox\walmart\${DATETIME}*.in"
}
elseif ($Action -eq "detail850andrew") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    & python $PSScriptRoot\edi850_podetails.py "Z:\ISOFT\inbox\walmart\*~850~*.in"
}
elseif ($Action -eq "move997") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    ./Move-files.ps1 Z:\ISOFT\inbox\walmart\*~997~*.in Z:\ISOFT\inbox\walmart\DSVSAMSC2026\${DATETIME}\997
}
elseif ($Action -eq "move850") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    ./Move-files.ps1 Z:\ISOFT\inbox\walmart\~${DATETIME}~*.in Z:\ISOFT\inbox\walmart\DSVSAMSC2026\${DATETIME}\850
}
elseif ($Action -eq "move824") {
    $DATETIME = $(Get-Date -Format "MMddyy")
    ./Move-files.ps1 Z:\ISOFT\inbox\walmart\*~824~*.in Z:\ISOFT\inbox\walmart\DSVSAMSC2026\${DATETIME}\824
}
else{
    Write-Host "Invalid action specified. Please use one of the following actions: check997, analyze850, analyze850andrew, detail850, detail850andrew, move997, move850."
}