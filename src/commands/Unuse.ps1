function Invoke-Unuse {
    param($Ctx)

    if ($Global:JmpDebug) {
        Log-Debug "Clearing Java environment from current session"
    }

    Clear-JavaEnvironment
}
