# src/commands/Invoke-Reset.ps1

function Invoke-Reset {
    param($Ctx)

    # No arguments provided - proceed with reset
    if ($Ctx.Args.Count -eq 1) {
        # Continue to main logic
    }
    # Handle --help / -h
    elseif ($Ctx.Args[1] -eq "--help" -or $Ctx.Args[1] -eq "-h") {
        Write-Warning "Usage: jmp reset [--system] [--force]"
        Write-Info "  Reset JMP to a clean state (clears session/user JAVA_HOME and cache)"
        Write-Info ""
        Write-Info "Options:"
        Write-Info "  --system  Clear system JAVA_HOME as well (requires admin)"
        Write-Info "  --force   Skip confirmation prompt"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp reset              # Clear session + user JAVA_HOME + cache"
        Write-Info "  jmp reset --system    # Also clear system JAVA_HOME"
        Write-Info "  jmp reset --force     # Skip confirmation"
        return
    }

    $clearSystem = $false
    $force = $false

    # Parse arguments (skip index 0 which is the command name)
    for ($i = 1; $i -lt $Ctx.Args.Count; $i++) {
        $arg = [string]$Ctx.Args[$i]
        $normalizedArg = $arg.ToLowerInvariant()
        if ($normalizedArg -eq "--system") {
            $clearSystem = $true
        } elseif ($normalizedArg -eq "--force") {
            $force = $true
        } else {
            Write-Warning "Unknown argument '$arg'. Usage: jmp reset [--system] [--force]"
            Write-Info "  --system  Clear system JAVA_HOME as well (requires admin)"
            Write-Info "  --force   Skip confirmation prompt"
            return
        }
    }

    # Check admin for --system
    if ($clearSystem) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-ErrorMsg "Administrator privileges are required to reset system JAVA_HOME."
            Write-Info "Run 'jmp reset' without --system, or run PowerShell as Administrator."
            return
        }
    }

    # Build warning message
    $cachePath = Join-Path $Script:ProjectRoot "java-versions.json"
    $cacheStatus = if (Test-Path $cachePath) { "will be deleted" } else { "does not exist" }

    Write-Host ""
    Write-Host "This will reset JMP to a clean state:" -ForegroundColor Yellow
    Write-Host "  - Current session Java environment will be cleared" -ForegroundColor Yellow
    Write-Host "  - User JAVA_HOME will be removed" -ForegroundColor Yellow
    if ($clearSystem) {
        Write-Host "  - System JAVA_HOME will be removed" -ForegroundColor Yellow
    }
    Write-Host "  - Cache file ($cacheStatus)" -ForegroundColor Yellow
    Write-Host ""

    # Confirm unless --force
    if (-not $force) {
        $confirm = Read-Host "Are you sure? [y/N]"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Info "Reset cancelled."
            return
        }
    }

    # 1. Clear current session
    Clear-JavaEnvironment | Out-Null

    # 2. Clear user JAVA_HOME
    $removedUser = Remove-PersistentJavaEnvironment -Scope "user"

    # 3. Clear system JAVA_HOME if requested
    if ($clearSystem) {
        $removedSystem = Remove-PersistentJavaEnvironment -Scope "system"
    }

    # 4. Delete cache file
    if (Test-Path $cachePath) {
        Remove-Item $cachePath -Force
        Write-Info "Cache file deleted."
    } else {
        Write-Info "No cache file to delete."
    }

    Write-Host ""
    Write-Success "JMP has been reset to a clean state."
    Write-Info "Run 'jmp scan' to rediscover Java installations."
}
