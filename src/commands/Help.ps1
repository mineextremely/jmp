function Invoke-Help {
    param($Ctx)
    
    Write-Warning "Usage: jmp <command> [args]"
    Write-Info ""
    Write-Info "Commands:"
    Write-Info "  scan                    - Discover Java installations (PATH-ES-first, then fd, then fallback)"
    Write-Info "  list                    - List all discovered Java"
    Write-Info "  use <version> [vendor]  - Switch Java version"
    Write-Info "  current                 - Show current JAVA_HOME"
    Write-Info "  version                 - Show script version"
    Write-Info "  help                    - Show this help"
    Write-Info ""
    Write-Info "Options:"
    Write-Info "  -debug                  - Enable debug output"
    Write-Info "  -fallback [1|2]         - Control scan fallback mode:"
    Write-Info "                            -fallback 1 = Skip Everything, use fd (if available)"
    Write-Info "                            -fallback 2 = Direct fallback scan (skip Everything and fd)"
    Write-Info "                            -fallback   = Same as -fallback 2"
    Show-Header
}