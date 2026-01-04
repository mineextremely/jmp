# src/java/Match.ps1

function Parse-JavaVersion {
    param([string]$VersionString)

    # 初始化版本对象
    $versionObj = [pscustomobject]@{
        original = $VersionString
        major = $null
        minor = $null
        patch = $null
        build = $null
        isJava8 = $false
    }

    # 处理Java 8的特殊格式: 1.8.0_472
    if ($VersionString -match '^1\.8\.0_(\d+)$') {
        $versionObj.major = 8
        $versionObj.minor = 0
        $versionObj.patch = [int]$matches[1]
        $versionObj.build = $matches[1]
        $versionObj.isJava8 = $true
        return $versionObj
    }

    # 处理标准格式: major.minor.patch
    if ($VersionString -match '^(\d+)\.(\d+)\.(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = [int]$matches[2]
        $versionObj.patch = [int]$matches[3]
        return $versionObj
    }

    # 处理可能的两段格式: major.minor
    if ($VersionString -match '^(\d+)\.(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = [int]$matches[2]
        $versionObj.patch = $null
        return $versionObj
    }

    # 处理只有major的格式: major
    if ($VersionString -match '^(\d+)$') {
        $versionObj.major = [int]$matches[1]
        $versionObj.minor = $null
        $versionObj.patch = $null
        return $versionObj
    }

    # 如果都不匹配，尝试更通用的解析
    # 移除下划线和加号等特殊字符，替换为点
    $normalized = $VersionString -replace '[_\+\+]', '.'
    $parts = $normalized -split '\.' | Where-Object { $_ -match '\d' }

    if ($parts.Count -ge 1) {
        $versionObj.major = [int]$parts[0]
        $versionObj.minor = if ($parts.Count -ge 2) { [int]$parts[1] } else { $null }
        $versionObj.patch = if ($parts.Count -ge 3) { [int]$parts[2] } else { $null }

        # 特殊处理：如果major=1且minor=8，则认为是Java 8
        if ($versionObj.major -eq 1 -and $versionObj.minor -eq 8) {
            $versionObj.major = 8
            $versionObj.minor = $null  # 用户输入"1.8"意味着他们只关心Java 8，不关心具体的minor/patch
            $versionObj.isJava8 = $true
        }
    }

    return $versionObj
}

function ConvertTo-SortableVersion {
    param([string]$VersionString)
    # 将下划线替换为点，以便System.Version可以解析
    $normalized = $VersionString -replace '_', '.'
    # 移除可能存在的非数字后缀（如+号等）
    # 但Java版本字符串通常是干净的，所以直接返回
    return $normalized
}