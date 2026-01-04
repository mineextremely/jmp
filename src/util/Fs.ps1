# src/util/Fs.ps1

function Load-Json($Path) {
    if (-not (Test-Path $Path)) { return $null }
    try {
        return Get-Content $Path -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to read JSON file: $Path"
        return $null
    }
}

function Save-Json($Path, $Obj) {
    try {
        $Obj | ConvertTo-Json -Depth 6 | Set-Content $Path -Encoding UTF8
    } catch {
        Write-Warning "Failed to save JSON file: $Path"
    }
}