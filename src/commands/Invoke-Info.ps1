# src/commands/Invoke-Info.ps1

function Invoke-Info {
    param($Ctx)

    if ($Ctx.Args.Count -lt 2) {
        Write-Warning "Usage: jmp info <version> [vendor]"
        Write-Info "  version: Java version to query (e.g., 17, 21)"
        Write-Info "  vendor:  Optional vendor name (e.g., temurin, zulu)"
        Write-Info ""
        Write-Info "Examples:"
        Write-Info "  jmp info 21           # Info about Java 21"
        Write-Info "  jmp info 17 temurin   # Info about Temurin Java 17"
        Write-Info "  jmp info 8            # Info about Java 8"
        return
    }

    $version = [string]$Ctx.Args[1]
    $vendor = if ($Ctx.Args.Count -ge 3) { [string]$Ctx.Args[2] } else { $null }

    $java = Find-Java -Version $version -Vendor $vendor
    if (-not $java) {
        return
    }

    Write-Info "Java Installation Details"
    Write-Host ("=" * 50) -ForegroundColor Cyan

    # Basic info
    Write-Host "Version   : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Version -ForegroundColor White

    Write-Host "Vendor    : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Vendor -ForegroundColor White

    Write-Host "Name      : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Name -ForegroundColor White

    Write-Host "Path      : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Path -ForegroundColor White

    Write-Host "Source    : " -NoNewline -ForegroundColor Gray
    Write-Host $java.Source -ForegroundColor White

    # Architecture detection
    Write-Host "Arch      : " -NoNewline -ForegroundColor Gray
    $arch = Get-JavaArchitecture $java.Path
    Write-Host $arch -ForegroundColor White

    Write-Host ""

    # Release file contents
    $releaseFile = Join-Path $java.Path "release"
    if (Test-Path $releaseFile) {
        Write-Info "Release File ($releaseFile)"
        Write-Host ("-" * 50) -ForegroundColor Cyan
        $releaseContent = Get-Content $releaseFile -Encoding UTF8
        foreach ($line in $releaseContent) {
            if ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim().Trim('"')
                Write-Host "$key = " -NoNewline -ForegroundColor DarkGray
                Write-Host $value -ForegroundColor White
            } else {
                Write-Host $line -ForegroundColor White
            }
        }
        Write-Host ""
    }

    # Java properties
    Write-Info "Java Properties (java -XshowSettings:properties -version)"
    Write-Host ("-" * 50) -ForegroundColor Cyan
    $javaExe = Join-Path $java.Path "bin\java.exe"
    if (Test-Path $javaExe) {
        try {
            $props = & $javaExe -XshowSettings:properties -version 2>&1 | Out-String
            $lines = $props -split "`n" | Where-Object { $_ -match '\S' }
            foreach ($line in $lines | Select-Object -First 20) {
                $trimmed = $line.Trim()
                if ($trimmed) {
                    Write-Host $trimmed -ForegroundColor White
                }
            }
        } catch {
            Write-Warning "Failed to get Java properties: $_"
        }
    } else {
        Write-Warning "Java executable not found at: $javaExe"
    }
}

function Get-JavaArchitecture {
    param([string]$JavaHome)

    # Try to detect from release file
    $releaseFile = Join-Path $JavaHome "release"
    if (Test-Path $releaseFile) {
        $content = Get-Content $releaseFile -Raw -Encoding UTF8
        if ($content -match 'OS_ARCH="([^"]+)"') {
            return $matches[1]
        }
        if ($content -match 'OS_NAME="([^"]+)"') {
            $osName = $matches[1]
            if ($osName -match 'Windows') {
                # Check for amd64 or x64
                if ($content -match 'OS_ARCH="([^"]+)"') {
                    return $matches[1]
                }
                # Heuristic: check if path contains x64 or amd64
                if ($JavaHome -match 'x64|amd64|win32|x86') {
                    return "x64"
                }
                return "x86"
            }
        }
    }

    # Fallback: check executable
    $javaExe = Join-Path $JavaHome "bin\java.exe"
    if (Test-Path $javaExe) {
        try {
            $output = & $javaExe -version 2>&1 | Out-String
            if ($output -match '64-Bit') {
                return "x64"
            }
        } catch {}
    }

    return "unknown"
}
