function Invoke-Pin {
    param($Ctx)

    if ($Ctx.Args.Count -lt 2) {
        Write-Warning "Usage: jmp pin <version> [vendor] [scope]"
        Write-Info "  version: Java version to pin (e.g., 17, 21)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info "  scope:   Optional scope, 'user' (default) or 'system'"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp pin 21                  # Pin Java 21 to user environment"
        Write-Info "  jmp pin 21 user            # Pin Java 21 to user environment"
        Write-Info "  jmp pin 21 system          # Pin Java 21 to system environment"
        Write-Info "  jmp pin 21 temurin         # Pin Temurin Java 21 to user environment"
        Write-Info "  jmp pin 21 temurin system  # Pin Temurin Java 21 to system environment"
        return
    }

    $version = $Ctx.Args[1]
    $vendor = $null
    $scope = "user"

    $argIndex = 2
    while ($argIndex -lt $Ctx.Args.Count) {
        $arg = $Ctx.Args[$argIndex]
        
        if ($arg -eq "user" -or $arg -eq "system") {
            $scope = $arg
        }
        else {
            $vendor = $arg
        }
        
        $argIndex++
    }

    if ($Global:JmpDebug) {
        Log-Debug "Calling Find-Java with version '$version' and vendor '$vendor'"
        Log-Debug "Scope: $scope"
    }

    $java = Find-Java -Version $version -Vendor $vendor
    if ($java) {
        Set-PersistentJavaEnvironment -Java $java -Scope $scope
    }
}
