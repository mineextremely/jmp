$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$Root/src/core/Bootstrap.ps1"

# 清理可能存在的全局调试变量
Remove-Variable -Name JmpDebug -Scope Global -ErrorAction SilentlyContinue

$JmpArgs = @()
$EnableDebug = $false
$ScanMode = "default"  # default, light, deep

$i = 0
while ($i -lt $args.Count) {
    $arg = $args[$i]
    
    if ($arg -eq "-debug") {
        $EnableDebug = $true
        $i++
    } elseif ($arg -eq "-light") {
        $ScanMode = "light"
        $i++
    } elseif ($arg -eq "-deep") {
        $ScanMode = "deep"
        $i++
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
        ScanMode = $ScanMode
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
    elseif ($Command -eq "unuse") {
        Invoke-Unuse $ctx
    }
    elseif ($Command -eq "pin") {
        Invoke-Pin $ctx
    }
    elseif ($Command -eq "unpin") {
        Invoke-Unpin $ctx
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