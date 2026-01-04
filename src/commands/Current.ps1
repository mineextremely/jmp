# src/commands/Current.ps1

function Invoke-Current {
    param($Ctx)
    
    if ($env:JAVA_HOME) {
        Write-Info "JAVA_HOME=$env:JAVA_HOME"
        try {
            $javaCmd = "$env:JAVA_HOME\bin\java.exe"
            if (Test-Path $javaCmd) {
                $javaVersion = & $javaCmd -version 2>&1 | Select-Object -First 1
                Write-Info "Java version: $javaVersion"
            } else {
                Write-Warning "Java executable not found at: $javaCmd"
            }
        } catch {
            Write-Warning "Java not accessible at $env:JAVA_HOME"
        }
    } else {
        Write-Warning "JAVA_HOME not set."
    }
}