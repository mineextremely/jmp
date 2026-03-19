# Fallback 扫描模块
# 包含 PATH 和常见目录的扫描功能

function Scan-Java-Fallback {
    $results = @()
    $candidates = @()

    # 1. PATH 下的 java.exe
    try {
        $cmds = Get-Command java -ErrorAction SilentlyContinue
        foreach ($c in $cmds) {
            if ($c.Source) {
                $javaHome = Split-Path (Split-Path $c.Source -Parent) -Parent
                $candidates += $javaHome
            }
        }
    } catch {}

    # 2. 常见目录
    $commonRoots = @(
        "$env:ProgramFiles\Java",
        "$env:ProgramFiles(x86)\Java",
        "$env:LOCALAPPDATA\Programs\Java",
        "$env:USERPROFILE\.jdks"
    ) | Where-Object { Test-Path $_ }

    foreach ($root in $commonRoots) {
        try {
            $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue
            foreach ($d in $dirs) {
                # 只要 bin\java.exe 存在，就加入
                $javaExe = Join-Path $d.FullName "bin\java.exe"
                if (Test-Path $javaExe) {
                    $candidates += $d.FullName
                }
            }
        } catch {}
    }

    # 去重
    $candidates = $candidates | Sort-Object -Unique

    # 构建结果对象
    foreach ($javaHome in $candidates) {
        $javaExe = Join-Path $javaHome "bin\java.exe"
        if (-not (Test-Path $javaExe)) { continue }

        # 尝试获取版本
        $ver = ""
        try {
            $verLine = & $javaExe -version 2>&1 | Select-Object -First 1
            if ($verLine -match '"([\d._]+)"') { $ver = $matches[1] }
        } catch {}

        $results += [pscustomobject]@{
            name = Split-Path $javaHome -Leaf
            version = $ver
            versionObj = Parse-JavaVersion $ver
            vendor = Detect-Vendor $javaHome
            path = $javaHome
            source = "fallback"
        }
    }

    return $results
}