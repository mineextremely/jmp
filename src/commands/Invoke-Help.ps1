function Invoke-Help {
    param($Ctx)

    Write-Warning "Usage: jmp <command> [args]"
    Write-Info ""
    Write-Info "Commands:"
    Write-Info "  scan    - Discover Java installations"
    Write-Info "  list    - List all discovered Java"
    Write-Info "  use     - Switch Java version for current session"
    Write-Info "  unuse   - Clear Java environment from current session"
    Write-Info "  pin     - Pin Java version to user/system environment"
    Write-Info "  unpin   - Remove pinned Java from user/system environment"
    Write-Info "  current - Show current JAVA_HOME"
    Write-Info "  version - Show script version"
    Write-Info "  help    - Show this help"
    Write-Info ""
    Write-Info "Examples:"
    Write-Info "  jmp scan              # Scan for Java installations"
    Write-Info "  jmp use 21 temurin    # Use Temurin Java 21"
    Write-Info "  jmp pin 21 system     # Pin Java 21 to system (needs admin)"
    Write-Info ""
    Write-Info "Options:"
    Write-Info "  -debug          - Enable debug output"
    Write-Info "  -fallback [1|2] - Control scan fallback mode"
    Write-Info ""
    Write-Info "Run 'jmp <command>' without args for command-specific help"
    Show-Header
}