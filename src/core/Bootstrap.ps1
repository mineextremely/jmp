# src/core/Bootstrap.ps1

$Script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Script:SrcRoot     = Join-Path $ProjectRoot "src"

Get-ChildItem -Path $SrcRoot -Recurse -Filter "*.ps1" |
    Where-Object { $_.FullName -ne $PSCommandPath } |
    ForEach-Object { . $_.FullName }
