# src/commands/List.ps1

function Invoke-List {
    param($Ctx)
    
    $data = Load-Json (Join-Path $Script:ProjectRoot "java-versions.json")
    if (-not $data) {
        Write-Warning "No scan data found. Run 'jmp scan' first."
        return
    }

    if ($data.Count -eq 0) {
        Write-Warning "No Java installations found. Please run 'jmp scan' to discover Java installations."
        return
    }

    Write-Info "Available Java installations:"
    $data |
        Sort-Object { 
            if ($_.versionObj -and $_.versionObj.major -ne $null) {
                # 使用解析后的版本对象进行排序
                $major = $_.versionObj.major
                $minor = if ($_.versionObj.minor -ne $null) { $_.versionObj.minor } else { 0 }
                $patch = if ($_.versionObj.patch -ne $null) { $_.versionObj.patch } else { 0 }
                # 创建可排序的字符串
                "{0:D4}.{1:D4}.{2:D4}" -f $major, $minor, $patch
            } else {
                # 回退到原始版本字符串
                $_.version
            }
        } |
        Format-Table version, vendor, name, source -AutoSize
}