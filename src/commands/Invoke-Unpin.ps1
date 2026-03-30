function Invoke-Unpin {
    param($Ctx)

    $scope = "user"

    if ($Ctx.Args.Count -ge 2) {
        $arg = [string]$Ctx.Args[1]
        $normalizedArg = $arg.ToLowerInvariant()
        if ($normalizedArg -eq "user" -or $normalizedArg -eq "system") {
            $scope = $normalizedArg
        } else {
            Write-Warning "Unexpected scope '$arg'. Usage: jmp unpin [user|system]"
            return
        }
    }

    if ($Ctx.Args.Count -gt 2) {
        Write-Warning "Too many arguments. Usage: jmp unpin [user|system]"
        return
    }

    if ($Global:JmpDebug) {
        Log-Debug "Unpinning Java from $scope environment"
    }

    $removed = Remove-PersistentJavaEnvironment -Scope $scope
    if ($removed -and $scope -eq "user") {
        Clear-JavaEnvironment | Out-Null
        Write-Info "Current session was cleared to match the unpinned user environment."
    }
}
