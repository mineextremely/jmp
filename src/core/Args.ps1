function Parse-JmpArgs {
    param([string[]]$InputArgs)

    [string[]]$JmpArgs = @()
    $EnableDebug = $false

    $i = 0
    while ($i -lt $InputArgs.Count) {
        $arg = $InputArgs[$i]
        
        if ($arg -eq "-debug") {
            $EnableDebug = $true
            $i++
        } else {
            # 强制转换为字符串，避免数字截断
            $JmpArgs = @($JmpArgs; "$($arg)")
            $i++
        }
    }

    if ($EnableDebug) {
        Write-Host "Debug: Raw JmpArgs count: $($JmpArgs.Count)" -ForegroundColor Gray
        for ($i = 0; $i -lt $JmpArgs.Count; $i++) {
            Write-Host "Debug: Raw JmpArgs[$i]: '$($JmpArgs[$i])' (Type: $($JmpArgs[$i].GetType().Name))" -ForegroundColor Gray
        }
    }

    $Command = if ($JmpArgs.Count -gt 0) { $JmpArgs[0] } else { $null }
    $Params  = if ($JmpArgs.Count -gt 1) { $JmpArgs[1..($JmpArgs.Count-1)] } else { @() }

    New-JmpContext `
        -Command $Command `
        -Params  $Params `
        -Debug   $EnableDebug
}

function Invoke-JmpCommand {
    param($Ctx)

    if ($Ctx.Debug) {
        $Global:JmpDebug = $true
    }

    switch ($Ctx.Command) {
        "scan"    { Invoke-Scan $Ctx }
        "list"    { Invoke-List $Ctx }
        "use"     { Invoke-Use $Ctx }
        "unuse"   { Invoke-Unuse $Ctx }
        "pin"     { Invoke-Pin $Ctx }
        "unpin"   { Invoke-Unpin $Ctx }
        "current" { Invoke-Current $Ctx }
        "version" { Invoke-Version $Ctx }
        "help"    { Invoke-Help $Ctx }
        default   { Invoke-Help $Ctx }
    }
}
