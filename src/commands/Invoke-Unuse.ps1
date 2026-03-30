function Invoke-Unuse {
    param($Ctx)

    if ($Ctx.Args.Count -gt 1) {
        Write-Warning "Too many arguments. Usage: jmp unuse"
        return
    }

    if ($Global:JmpDebug) {
        Log-Debug "Clearing Java environment from current session"
    }

    Clear-JavaEnvironment | Out-Null
}
