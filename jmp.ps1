$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$Root/src/core/Bootstrap.ps1"

$JmpArgs = @()
$EnableDebug = $false
$FallbackMode = 0

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    
    if ($arg -eq "-debug") {
        $EnableDebug = $true
        $i++
    } elseif ($arg -eq "-fallback") {
        if ($i + 1 -lt $args.Count -and $args[$i + 1] -match '^[12]$') {
            $FallbackMode = [int]$args[$i + 1]
            $i += 2
        } else {
            $FallbackMode = 2
            $i++
        }
    } else {
        if ($JmpArgs.Count -eq 0) {
            $JmpArgs = @($arg)
        } else {
            $JmpArgs += $arg
        }
        $i++
    }
}

if ($EnableDebug) {
    $Global:JmpDebug = $true
}

if ($JmpArgs.Count -eq 0) {
    Invoke-Help $null
} else {
    $Command = $JmpArgs[0]
    
    $ctx = @{
        Args = $JmpArgs
        Debug = $EnableDebug
        FallbackMode = $FallbackMode
    }
    
    if ($Command -eq "scan") {
        Invoke-Scan $ctx
    }
    elseif ($Command -eq "list") {
        Invoke-List $ctx
    }
    elseif ($Command -eq "use") {
        Invoke-Use $ctx
    }
    elseif ($Command -eq "current") {
        Invoke-Current $ctx
    }
    elseif ($Command -eq "version") {
        Invoke-Version $ctx
    }
    elseif ($Command -eq "help") {
        Invoke-Help $ctx
    }
    else {
        Invoke-Help $ctx
    }
}

if ($EnableDebug) {
    Show-Header
}