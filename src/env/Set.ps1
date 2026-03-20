Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@

function Set-JavaEnvironment {
    param($Java)

    if (-not $Java) {
        Write-ErrorMsg "No Java installation provided."
        return $false
    }

    $oldJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $Java.Path

    # 使用旧的 JAVA_HOME 清理 PATH 中的旧 Java bin 路径
    if ($oldJavaHome) {
        $env:PATH = $env:PATH -replace [regex]::Escape("$oldJavaHome\bin;"), ""
        $env:PATH = $env:PATH -replace [regex]::Escape("$oldJavaHome\bin"), ""
    }

    # 过滤掉所有残留的 Java bin 路径
    $pathParts = $env:PATH -split ';'
    $filteredParts = @()
    foreach ($part in $pathParts) {
        $trimmedPart = $part.Trim()
        if ($trimmedPart -and -not ($trimmedPart -imatch "\\bin$" -and (Test-Path (Join-Path $trimmedPart "java.exe") -ErrorAction SilentlyContinue))) {
            $filteredParts += $trimmedPart
        }
    }

    $env:PATH = "$($Java.Path)\bin;" + ($filteredParts -join ';')
    
    Write-Success "Switched to Java $($Java.VersionObj.major) ($($Java.Vendor))"
    Write-Info "JAVA_HOME = $($Java.Path)"
    Write-Info "Version: $($Java.Version)"
    Write-Info "Added to PATH: $($Java.Path)\bin"
    
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

function Set-PersistentJavaEnvironment {
    param(
        $Java,
        [ValidateSet("user", "system")]
        [string]$Scope = "user"
    )

    if (-not $Java) {
        Write-ErrorMsg "No Java installation provided."
        return $false
    }

    if ($Scope -eq "system") {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-ErrorMsg "Administrator privileges are required to set system-level environment variables."
            Write-Info "Please run PowerShell as Administrator and try again."
            return $false
        }
    }

    try {
        $target = if ($Scope -eq "system") { [EnvironmentVariableTarget]::Machine } else { [EnvironmentVariableTarget]::User }
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $Java.Path, $target)

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", $target)
        $newJavaBin = "$($Java.Path)\bin"
        
        $pathParts = $currentPath -split ';'
        $filteredParts = @()
        foreach ($part in $pathParts) {
            $trimmedPart = $part.Trim()
            if (-not ($trimmedPart -imatch "\\bin$" -and (Test-Path (Split-Path $trimmedPart)))) {
                $filteredParts += $trimmedPart
            }
        }
        
        $newPath = "$newJavaBin;" + ($filteredParts -join ';')
        [Environment]::SetEnvironmentVariable("PATH", $newPath, $target)

        if ($Scope -eq "system") {
            $result = [IntPtr]::Zero
            [Win32]::SendMessageTimeout(0xFFFF, 0x001A, [IntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$result) | Out-Null
        }

        $scopeText = if ($Scope -eq "system") { "system" } else { "user" }
        Write-Success "Pinned Java $($Java.VersionObj.major) ($($Java.Vendor)) to $scopeText environment"
        Write-Info "JAVA_HOME = $($Java.Path)"
        Write-Info "Version: $($Java.Version)"
        Write-Info "Added to PATH: $($Java.Path)\bin"
        Write-Info "Changes will take effect in new terminal sessions."

        return $true
    } catch {
        Write-ErrorMsg "Failed to set persistent environment variables: $_"
        return $false
    }
}

function Remove-PersistentJavaEnvironment {
    param(
        [ValidateSet("user", "system")]
        [string]$Scope = "user"
    )

    if ($Scope -eq "system") {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-ErrorMsg "Administrator privileges are required to remove system-level environment variables."
            Write-Info "Please run PowerShell as Administrator and try again."
            return $false
        }
    }

    try {
        $target = if ($Scope -eq "system") { [EnvironmentVariableTarget]::Machine } else { [EnvironmentVariableTarget]::User }
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, $target)

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", $target)
        if ($currentPath) {
            $pathParts = $currentPath -split ';'
            $filteredParts = @()
            foreach ($part in $pathParts) {
                $trimmedPart = $part.Trim()
                if (-not ($trimmedPart -imatch "\\bin$" -and (Test-Path (Split-Path $trimmedPart)))) {
                    $filteredParts += $trimmedPart
                }
            }
            
            $newPath = $filteredParts -join ';'
            [Environment]::SetEnvironmentVariable("PATH", $newPath, $target)
        }

        if ($Scope -eq "system") {
            $result = [IntPtr]::Zero
            [Win32]::SendMessageTimeout(0xFFFF, 0x001A, [IntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$result) | Out-Null
        }

        $scopeText = if ($Scope -eq "system") { "system" } else { "user" }
        Write-Success "Removed Java from $scopeText environment"
        Write-Info "JAVA_HOME has been removed"
        Write-Info "Java paths have been removed from PATH"
        Write-Info "Changes will take effect in new terminal sessions."

        return $true
    } catch {
        Write-ErrorMsg "Failed to remove persistent environment variables: $_"
        return $false
    }
}

function Clear-JavaEnvironment {
    # 先保存旧值用于精确清理，再清除 JAVA_HOME
    $oldJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $null

    if ($oldJavaHome) {
        $env:PATH = $env:PATH -replace [regex]::Escape("$oldJavaHome\bin;"), ""
        $env:PATH = $env:PATH -replace [regex]::Escape("$oldJavaHome\bin"), ""
    }

    # 过滤掉所有残留的 Java bin 路径
    $pathParts = $env:PATH -split ';'
    $filteredParts = @()
    foreach ($part in $pathParts) {
        $trimmedPart = $part.Trim()
        if ($trimmedPart -and -not ($trimmedPart -imatch "\\bin$" -and (Test-Path (Join-Path $trimmedPart "java.exe") -ErrorAction SilentlyContinue))) {
            $filteredParts += $trimmedPart
        }
    }

    $env:PATH = $filteredParts -join ';'
    
    Write-Success "Cleared Java environment from current session"
    Write-Info "JAVA_HOME has been removed"
    Write-Info "Java paths have been removed from PATH"
    
    return $true
}
