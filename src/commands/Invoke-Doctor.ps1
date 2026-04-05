# src/commands/Invoke-Doctor.ps1

function Invoke-Doctor {
    param($Ctx)

    Write-Info "JMP Doctor - Running diagnostics..."
    Write-Host ""

    $issues = @()
    $warnings = @()
    $passed = @()

    # 1. Check cache file existence and age
    $cachePath = Join-Path $Script:ProjectRoot "java-versions.json"
    if (-not (Test-Path $cachePath)) {
        $issues += "Cache file not found. Run 'jmp scan' first."
    } else {
        $cacheAge = (Get-Date) - (Get-Item $cachePath).LastWriteTime
        if ($cacheAge.TotalHours -gt 24) {
            $issues += "Cache file is older than 24 hours ($([Math]::Round($cacheAge.TotalHours)) hours). Run 'jmp scan' to update."
        } else {
            $passed += "Cache file is fresh ($([Math]::Round($cacheAge.TotalHours, 1)) hours old)"

            # Check cache content
            $data = Load-Json $cachePath
            if ($data -and $data.Count -gt 0) {
                $passed += "Cache contains $($data.Count) Java installation(s)"
            } else {
                $issues += "Cache file exists but contains no Java installations. Run 'jmp scan'."
            }
        }
    }

    # 2. Check fd.exe existence
    $binDir = Join-Path $Script:ProjectRoot "bin"
    $fdPath = Join-Path $binDir "fd.exe"
    if (-not (Test-Path $fdPath)) {
        $warnings += "fd.exe not found. Deep scan will prompt to download."
    } else {
        $fdVersion = & $fdPath --version 2>&1 | Select-Object -First 1
        $passed += "fd.exe is installed ($fdVersion)"
    }

    # 3. Check PATH pollution (duplicate Java entries)
    $pathParts = $env:PATH -split ';' | Where-Object { $_ -match '\\bin$' -and (Test-Path (Join-Path $_ "java.exe") -ErrorAction SilentlyContinue) }
    if ($pathParts.Count -gt 1) {
        $warnings += "Multiple Java bin directories found in PATH:"
        foreach ($p in $pathParts) {
            $warnings += "  - $p"
        }
    } elseif ($pathParts.Count -eq 1) {
        $passed += "PATH has exactly one Java bin directory"
    }

    # 4. Check JAVA_HOME consistency
    if ($env:JAVA_HOME) {
        $javaInPath = $pathParts | Select-Object -First 1
        if ($javaInPath) {
            $javaHomeFromPath = Split-Path $javaInPath -Parent
            if ($javaHomeFromPath -ne $env:JAVA_HOME) {
                $warnings += "JAVA_HOME ('$env:JAVA_HOME') differs from PATH Java ('$javaHomeFromPath')"
            } else {
                $passed += "JAVA_HOME matches PATH Java"
            }
        }
    } else {
        $warnings += "JAVA_HOME is not set"
    }

    # 5. Check vendor priority config
    $vendorConfig = Join-Path $Script:ProjectRoot "config\vendor-priority.json"
    if (-not (Test-Path $vendorConfig)) {
        $warnings += "Vendor priority config not found, using defaults"
    } else {
        $config = Load-Json $vendorConfig
        if ($config -and $config.priority) {
            $passed += "Vendor priority configured: $($config.priority -join ', ')"
        } else {
            $warnings += "Vendor priority config is malformed"
        }
    }

    # 6. Check for fd version directory pollution
    $fdVersionDirs = Get-ChildItem $Script:ProjectRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^fd-v' }
    if ($fdVersionDirs) {
        $warnings += "Found fd version directories (should be in bin/):"
        foreach ($d in $fdVersionDirs) {
            $warnings += "  - $($d.Name)"
        }
    }

    # Output results
    Write-Host "Results:" -ForegroundColor Cyan
    Write-Host ("-" * 50) -ForegroundColor Cyan

    if ($passed.Count -gt 0) {
        Write-Host "[PASS] " -ForegroundColor Green -NoNewline
        Write-Host "$($passed.Count) checks passed" -ForegroundColor White
        foreach ($p in $passed) {
            Write-Host "  - $p" -ForegroundColor DarkGreen
        }
        Write-Host ""
    }

    if ($warnings.Count -gt 0) {
        Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
        Write-Host "$($warnings.Count) warnings" -ForegroundColor White
        foreach ($w in $warnings) {
            Write-Host "  - $w" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    if ($issues.Count -gt 0) {
        Write-Host "[FAIL] " -ForegroundColor Red -NoNewline
        Write-Host "$($issues.Count) issues need attention" -ForegroundColor White
        foreach ($i in $issues) {
            Write-Host "  - $i" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Summary
    if ($issues.Count -eq 0) {
        Write-Success "JMP is healthy!"
        if ($warnings.Count -gt 0) {
            Write-Info "Some warnings were found but don't affect functionality."
        }
    } else {
        Write-ErrorMsg "JMP has issues that need to be resolved."
        Write-Info "Run 'jmp scan' to refresh cache, or fix the issues above."
    }
}
