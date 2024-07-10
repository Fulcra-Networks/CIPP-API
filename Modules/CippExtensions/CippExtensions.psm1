$Public = @(Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue)
$IronScales = @(Get-ChildItem -Path $PSScriptRoot\IronScales\*.ps1 -ErrorAction SilentlyContinue)
$Autotask = @(Get-ChildItem -Path $PSScriptRoot\Autotask\*.ps1 -ErrorAction SilentlyContinue)
$Functions = $Public + $Private + $IronScales + $Autotask
foreach ($import in @($Functions)) {
    try {
        . $import.FullName
    } catch {
        Write-Error -Message "Failed to import function $($import.FullName): $_"
    }
}

Export-ModuleMember -Function $Functions.BaseName -Alias *
