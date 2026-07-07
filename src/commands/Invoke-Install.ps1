# src/commands/Invoke-Install.ps1

function Invoke-Install {
    param($Ctx)

    # No args — show usage
    if ($Ctx.Args.Count -lt 2) {
        Write-Warning "Usage: jmp install <version> [vendor] [-path <dir>]"
        Write-Info "  version: Java version to install (e.g., 21, 17, 8)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info "  -path:   Custom install directory (default: bin/jdks/)"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp install 21               # Install latest Java 21"
        Write-Info "  jmp install 21 temurin       # Install Temurin Java 21"
        Write-Info "  jmp install 17 -path D:\\\\Java  # Install to custom path"
        return
    }

    # Handle --help / -h
    $secondArg = [string]$Ctx.Args[1]
    if ($secondArg -eq "--help" -or $secondArg -eq "-h") {
        Write-Warning "Usage: jmp install <version> [vendor] [-path <dir>]"
        Write-Info "  Download and install a JDK from the Foojay Disco API."
        Write-Info ""
        Write-Info "  version: Java major version (e.g., 21, 17, 8)"
        Write-Info "  vendor:  Optional vendor (e.g., temurin, zulu, corretto)"
        Write-Info "  -path:   Custom install directory"
        Write-Info ""
        Write-Info "  Default install path: bin/jdks/<vendor>-<version>/"
        Write-Info "  Vendor auto-selected by priority if not specified."
        return
    }

    $version = $secondArg
    $vendor = $null
    $customPath = $null

    # Parse remaining args
    for ($i = 2; $i -lt $Ctx.Args.Count; $i++) {
        $arg = [string]$Ctx.Args[$i]
        if ($arg -eq "-path" -or $arg -eq "--path") {
            $i++
            if ($i -lt $Ctx.Args.Count) {
                $customPath = [string]$Ctx.Args[$i]
            } else {
                Write-Warning "-path requires a directory argument."
                return
            }
        } elseif (-not $vendor) {
            $vendor = $arg
        } else {
            Write-Warning "Unknown argument '$arg'. Usage: jmp install <version> [vendor] [-path <dir>]"
            return
        }
    }

    # Validate version is numeric
    if ($version -notmatch '^\d+$') {
        Write-Warning "Invalid version '$version'. Please specify a major version number (e.g., 21, 17, 8)."
        return
    }

    if ($Global:JmpDebug) {
        Log-Debug "Install: version=$version, vendor=$vendor, path=$customPath"
    }

    # Find package via API
    $package = Find-JavaPackage -Version $version -Vendor $vendor
    if (-not $package) {
        return
    }

    # Determine install path
    $dirName = "$($package.JmpVendor)-$($package.major_version)"
    if (-not $customPath) {
        $jdksDir = Join-Path $Script:ProjectRoot "bin\jdks"
        $installPath = Join-Path $jdksDir $dirName
    } else {
        $installPath = Join-Path $customPath $dirName
    }

    # Confirm with user
    Write-Host ""
    Write-Host "Installation details:" -ForegroundColor Cyan
    Write-Host "  Version   : " -NoNewline -ForegroundColor Gray
    Write-Host "$($package.java_version) ($($package.JmpVendor))" -ForegroundColor White

    if ($package.VersionMeta) {
        $meta = $package.VersionMeta
        $tosLabel = $meta.termOfSupport.ToUpper()
        $tosColor = if ($tosLabel -eq "LTS") { "Green" } else { "Yellow" }
        Write-Host "  Support   : " -NoNewline -ForegroundColor Gray
        Write-Host $tosLabel -ForegroundColor $tosColor -NoNewline
        if ($meta.maintained) {
            Write-Host "  (maintained)" -ForegroundColor Green
        } else {
            Write-Host "  (unmaintained)" -ForegroundColor Red
        }
    }

    Write-Host "  Size      : " -NoNewline -ForegroundColor Gray
    Write-Host "$([Math]::Round($package.size / 1MB, 1)) MB" -ForegroundColor White
    Write-Host "  Install to: " -NoNewline -ForegroundColor Gray
    Write-Host $installPath -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Proceed with installation? [Y/n]"
    if ($confirm -ne "" -and $confirm -notmatch "^[Yy]") {
        Write-Info "Installation cancelled."
        return
    }

    # Download and extract
    $installed = Install-JavaPackage -Package $package -InstallPath $installPath
    if (-not $installed) {
        return
    }

    # Refresh scan cache
    Write-Info "Refreshing scan cache..."
    $cachePath = Join-Path $Script:ProjectRoot "java-versions.json"
    $existing = if (Test-Path $cachePath) { @(Load-Json $cachePath) } else { @() }

    $releaseInfo = Read-JavaRelease $installPath
    $entryVersion = if ($releaseInfo -and $releaseInfo.version) { $releaseInfo.version } else { $package.java_version }
    $entryRtVer   = if ($releaseInfo) { $releaseInfo.runtimeVersion } else { "" }
    $entryLts     = if ($releaseInfo) { $releaseInfo.isLts } else { $false }

    $newEntry = [pscustomobject]@{
        name           = Split-Path $installPath -Leaf
        version        = $entryVersion
        versionObj     = Parse-JavaVersion $entryVersion
        vendor         = Detect-Vendor $installPath
        path           = $installPath
        source         = "install"
        runtimeVersion = $entryRtVer
        isLts          = $entryLts
    }

    $allResults = @($newEntry) + @($existing)
    Save-Json $cachePath $allResults

    Write-Host ""
    Write-Info "Run 'jmp use $($package.major_version) $($package.JmpVendor)' to switch to this Java."
}
