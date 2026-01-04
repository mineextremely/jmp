function Invoke-Use {
    param($Ctx)

    if ($Ctx.Params.Count -lt 1) {
        Write-Warning "Usage: jmp use <version> [vendor]"
        return
    }

    $version = $Ctx.Params[0]
    $vendor  = if ($Ctx.Params.Count -ge 2) { $Ctx.Params[1] } else { $null }

    if ($Global:JmpDebug) { 
        Log-Debug "Calling Find-Java with version '$version' and vendor '$vendor'"
    }

    $java = Find-Java -Version $version -Vendor $vendor
    if ($java) {
        Set-JavaEnvironment $java
    }
}
