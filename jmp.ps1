# jmp.ps1
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$Root/src/core/Bootstrap.ps1"

Show-Header

# 直接处理命令，不通过参数解析
if ($args.Count -eq 0) {
    Invoke-Help $null
} else {
    $command = $args[0]
    $params = if ($args.Count -gt 1) { $args[1..($args.Count-1)] } else { @() }
    
    switch ($command) {
        "scan"    { Invoke-Scan @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        "list"    { Invoke-List @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        "use"     { Invoke-Use @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        "current" { Invoke-Current @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        "version" { Invoke-Version @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        "help"    { Invoke-Help @{ Params = $params; Debug = $false; FallbackMode = 0 } }
        default   { Invoke-Help @{ Params = $params; Debug = $false; FallbackMode = 0 } }
    }
}