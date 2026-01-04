function Set-JavaEnvironment {
    param($Java)

    if (-not $Java) {
        Write-ErrorMsg "No Java installation provided."
        return $false
    }

    $env:JAVA_HOME = $Java.Path
    # 移除旧的JAVA_HOME路径，然后添加新的路径
    $env:PATH = $env:PATH -replace [regex]::Escape("$env:JAVA_HOME\bin;"), ""
    $env:PATH = $env:PATH -replace [regex]::Escape("$env:JAVA_HOME\bin"), ""
    $env:PATH = "$($Java.Path)\bin;$env:PATH"
    
    Write-Success "Switched to Java $($Java.VersionObj.major) ($($Java.Vendor))"
    Write-Info "JAVA_HOME = $($Java.Path)"
    Write-Info "Version: $($Java.Version)"
    Write-Info "Added to PATH: $($Java.Path)\bin"
    
    # 验证Java版本
    try {
        $javaCmd = "$($Java.Path)\bin\java.exe"
        if (Test-Path $javaCmd) {
            $javaVersion = & $javaCmd -version 2>&1 | Select-Object -First 1
            Write-Info "Java version: $javaVersion"
        } else {
            Write-Warning "Java executable not found at: $javaCmd"
        }
    } catch {
        Write-Warning "Could not verify Java installation: $_"
    }

    return $true
}