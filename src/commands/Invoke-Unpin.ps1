function Invoke-Unpin {
    param($Ctx)

    $scope = "user"

    if ($Ctx.Args.Count -ge 2) {
        $arg = $Ctx.Args[1]
        if ($arg -eq "user" -or $arg -eq "system") {
            $scope = $arg
        }
    }

    if ($Global:JmpDebug) {
        Log-Debug "Unpinning Java from $scope environment"
    }

    Remove-PersistentJavaEnvironment -Scope $scope
}
