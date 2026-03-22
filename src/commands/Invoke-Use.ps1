function Invoke-Use {
    param($Ctx)

    if ($Ctx.Args.Count -lt 2) {
        Write-Warning "Usage: jmp use <version> [vendor]"
        Write-Info "  version: Java version to use (e.g., 17, 21)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp use 21           # Use Java 21 (highest priority vendor)"
        Write-Info "  jmp use 21 temurin   # Use Temurin Java 21"
        Write-Info "  jmp use 8            # Use Java 8"
        return
    }

    if ($Ctx.Args.Count -gt 3) {
        Write-Warning "Too many arguments. Usage: jmp use <version> [vendor]"
        return
    }

    $version = $Ctx.Args[1]
    $vendor = if ($Ctx.Args.Count -eq 3) { [string]$Ctx.Args[2] } else { $null }

    if ($Global:JmpDebug) {
        Log-Debug "Calling Find-Java with version '$version' and vendor '$vendor'"
    }

    $java = Find-Java -Version $version -Vendor $vendor
    if ($java) {
        Set-JavaEnvironment $java | Out-Null
    }
}
