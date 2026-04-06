# src/commands/Invoke-Which.ps1

function Invoke-Which {
    param($Ctx)

    # No arguments - show usage
    if ($Ctx.Args.Count -eq 1) {
        Write-Warning "Usage: jmp which <version> [vendor]"
        Write-Info "  version: Java version to query (e.g., 17, 21)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp which 21           # Show which Java 21 would be selected"
        Write-Info "  jmp which 17 temurin   # Show which Temurin Java 17 would be selected"
        Write-Info "  jmp which --current     # Show current session Java"
        return
    }

    # jmp which --current
    if ($Ctx.Args[1] -eq "--current") {
        if ($env:JAVA_HOME) {
            Write-Info "Current session Java:"
            Write-Host "  JAVA_HOME : " -NoNewline -ForegroundColor Gray
            Write-Host $env:JAVA_HOME -ForegroundColor White

            $javaExe = "$env:JAVA_HOME\bin\java.exe"
            if (Test-Path $javaExe) {
                try {
                    $version = & $javaExe -version 2>&1 | Select-Object -First 1
                    Write-Host "  Version   : " -NoNewline -ForegroundColor Gray
                    Write-Host $version.Trim() -ForegroundColor White
                } catch {
                    Write-Warning "Could not get Java version"
                }
            }
        } else {
            Write-Warning "No Java is set in current session."
            Write-Info "Use 'jmp use <version>' to switch Java."
        }
        return
    }

    # jmp which --help / -h
    if ($Ctx.Args[1] -eq "--help" -or $Ctx.Args[1] -eq "-h") {
        Write-Warning "Usage: jmp which <version> [vendor]"
        Write-Info "  version: Java version to query (e.g., 17, 21)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp which 21           # Show which Java 21 would be selected"
        Write-Info "  jmp which 17 temurin   # Show which Temurin Java 17 would be selected"
        Write-Info "  jmp which --current     # Show current session Java"
        return
    }

    $version = [string]$Ctx.Args[1]
    $vendor = if ($Ctx.Args.Count -ge 3) { [string]$Ctx.Args[2] } else { $null }

    $java = Find-Java -Version $version -Vendor $vendor
    if (-not $java) {
        return
    }

    Write-Info "Selected Java:"
    Write-Host "  Version   : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Version -ForegroundColor White

    Write-Host "  Vendor    : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Vendor -ForegroundColor White

    Write-Host "  Path      : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Path -ForegroundColor White

    Write-Host "  Source    : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Source -ForegroundColor White

    # Architecture detection
    Write-Host "  Arch      : " -NoNewline -ForegroundColor Gray
    $arch = Get-JavaArchitecture $java.Path
    Write-Host $arch -ForegroundColor White
}
