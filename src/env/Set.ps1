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

function Get-KnownJavaBinEntries {
    $javaBins = New-Object System.Collections.Generic.List[string]

    $jsonPath = Join-Path $Script:ProjectRoot "java-versions.json"
    if (Test-Path $jsonPath) {
        try {
            $jsonData = Load-Json $jsonPath
            foreach ($item in @($jsonData)) {
                if ($item.path) {
                    $javaBins.Add(([IO.Path]::GetFullPath((Join-Path $item.path "bin"))))
                }
            }
        } catch {
            if ($Global:JmpDebug) {
                Log-Debug "Failed to load known Java installations from cache: $_"
            }
        }
    }

    return @($javaBins | Sort-Object -Unique)
}

function Test-IsJavaBinEntry {
    param(
        [string]$PathEntry,
        [string[]]$KnownJavaBins = @()
    )

    if (-not $PathEntry) {
        return $false
    }

    $normalizedEntry = $PathEntry.Trim().TrimEnd('\')
    if (-not $normalizedEntry) {
        return $false
    }

    foreach ($knownBin in $KnownJavaBins) {
        if ($normalizedEntry -ieq $knownBin.TrimEnd('\')) {
            return $true
        }
    }

    $javaExe = Join-Path $normalizedEntry "java.exe"
    $releaseFile = Join-Path (Split-Path $normalizedEntry -Parent) "release"

    return (Test-Path $javaExe -ErrorAction SilentlyContinue) -and (Test-Path $releaseFile -ErrorAction SilentlyContinue)
}

function Remove-JavaBinEntriesFromPath {
    param(
        [string]$PathValue,
        [string[]]$ExtraJavaHomes = @()
    )

    $knownJavaBins = New-Object System.Collections.Generic.List[string]
    foreach ($knownBin in @(Get-KnownJavaBinEntries)) {
        $knownJavaBins.Add($knownBin.TrimEnd('\'))
    }
    foreach ($javaHome in @($ExtraJavaHomes | Where-Object { $_ })) {
        $knownJavaBins.Add(([IO.Path]::GetFullPath((Join-Path $javaHome "bin"))).TrimEnd('\'))
    }

    $filteredParts = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($PathValue -split ';')) {
        $trimmedPart = $part.Trim()
        if (-not $trimmedPart) {
            continue
        }

        if (Test-IsJavaBinEntry -PathEntry $trimmedPart -KnownJavaBins @($knownJavaBins)) {
            continue
        }

        if (-not ($filteredParts -contains $trimmedPart)) {
            $filteredParts.Add($trimmedPart)
        }
    }

    return ($filteredParts -join ';')
}

function Set-JavaEnvironment {
    param($Java)

    if (-not $Java) {
        Write-ErrorMsg "No Java installation provided."
        return $false
    }

    $oldJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $Java.Path

    $cleanPath = Remove-JavaBinEntriesFromPath -PathValue $env:PATH -ExtraJavaHomes @($oldJavaHome, $Java.Path)
    $javaBin = "$($Java.Path)\bin"
    $env:PATH = if ($cleanPath) { "$javaBin;$cleanPath" } else { $javaBin }

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
        $cleanPath = Remove-JavaBinEntriesFromPath -PathValue $currentPath -ExtraJavaHomes @($Java.Path)
        $newPath = if ($cleanPath) { "$newJavaBin;$cleanPath" } else { $newJavaBin }
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
        $oldJavaHome = [Environment]::GetEnvironmentVariable("JAVA_HOME", $target)
        [Environment]::SetEnvironmentVariable("JAVA_HOME", $null, $target)

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", $target)
        if ($currentPath) {
            $newPath = Remove-JavaBinEntriesFromPath -PathValue $currentPath -ExtraJavaHomes @($oldJavaHome)
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
    $oldJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $null
    $env:PATH = Remove-JavaBinEntriesFromPath -PathValue $env:PATH -ExtraJavaHomes @($oldJavaHome)

    Write-Success "Cleared Java environment from current session"
    Write-Info "JAVA_HOME has been removed"
    Write-Info "Java paths have been removed from PATH"

    return $true
}
