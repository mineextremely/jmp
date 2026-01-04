function Invoke-Use {
    param($Ctx)

    if ($Ctx.Args.Count -lt 2) {
        Write-Warning "Usage: jmp use <version> [vendor]"
        return
    }

    $version = $Ctx.Args[1]
    $vendor = if ($Ctx.Args.Count -ge 3) { $Ctx.Args[2] } else { $null }

    if ($Global:JmpDebug) {
        Log-Debug "Calling Find-Java with version '$version' and vendor '$vendor'"
    }

    $java = Find-Java -Version $version -Vendor $vendor
    if ($java) {
        Set-JavaEnvironment $java
    }
}