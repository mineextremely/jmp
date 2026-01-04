# src/java/Vendor.ps1

function Detect-Vendor($Path) {
    $pathLower = $Path.ToLower()
    $vendors = @()
    
    if ($pathLower -match "temurin|adoptium") { $vendors += "temurin" }
    if ($pathLower -match "graalvm") { $vendors += "graalvm" }
    if ($pathLower -match "zulu") { $vendors += "zulu" }
    if ($pathLower -match "oracle") { $vendors += "oracle" }
    
    # 如果没有检测到任何vendor，返回"unknown"
    if ($vendors.Count -eq 0) { return "unknown" }
    
    # 如果检测到多个vendor，返回第一个，但可以记录所有
    return $vendors[0]
}

function Get-VendorPriority {
    $vendorFile = Load-Json (Join-Path $Script:ProjectRoot "config\vendor-priority.json")
    if ($vendorFile -and $vendorFile.priority) {
        return $vendorFile.priority
    } else {
        # 默认优先级
        return @("temurin", "zulu", "oracle", "graalvm", "unknown")
    }
}