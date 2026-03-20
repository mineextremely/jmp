function New-JmpContext {
    param(
        [string]$Command,
        [string[]]$Params,
        [bool]$Debug
    )

    [pscustomobject]@{
        Command = $Command
        Params  = $Params
        Debug   = $Debug
    }
}
