function New-JmpContext {
    param(
        [string]$Command,
        [string[]]$Params,
        [bool]$Debug,
        [int]$FallbackMode = 0
    )

    [pscustomobject]@{
        Command = $Command
        Params  = $Params
        Debug   = $Debug
        FallbackMode = $FallbackMode
    }
}
