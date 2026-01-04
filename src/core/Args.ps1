function Parse-JmpArgs {
    param([string[]]$InputArgs)

    # 初始化参数数组
    [string[]]$JmpArgs = @()
    $EnableDebug = $false
    $FallbackMode = 0  # 0=自动, 1=跳过ES用FD, 2=直接fallback

    $i = 0
    while ($i -lt $InputArgs.Count) {
        $arg = $InputArgs[$i]
        
        if ($arg -eq "-debug") {
            $EnableDebug = $true
            $i++
        } elseif ($arg -eq "-fallback") {
            # 检查是否有下一个参数，且为数字
            if ($i + 1 -lt $InputArgs.Count -and $InputArgs[$i + 1] -match '^[12]$') {
                $FallbackMode = [int]$InputArgs[$i + 1]
                $i += 2
            } else {
                # 默认：-fallback 不带参数等价于 -fallback 2
                $FallbackMode = 2
                $i++
            }
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
        if ($FallbackMode -ne 0) {
            Write-Host "Debug: FallbackMode = $FallbackMode" -ForegroundColor Gray
        }
    }

    $Command = if ($JmpArgs.Count -gt 0) { $JmpArgs[0] } else { $null }
    $Params  = if ($JmpArgs.Count -gt 1) { $JmpArgs[1..($JmpArgs.Count-1)] } else { @() }

    New-JmpContext `
        -Command $Command `
        -Params  $Params `
        -Debug   $EnableDebug `
        -FallbackMode $FallbackMode
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
        "current" { Invoke-Current $Ctx }
        "version" { Invoke-Version $Ctx }
        "help"    { Invoke-Help $Ctx }
        default   { Invoke-Help $Ctx }
    }
}