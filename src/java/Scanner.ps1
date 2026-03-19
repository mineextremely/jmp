# src/java/Scanner.ps1
#
# 本文件已重构为模块化结构，原功能已拆分到以下模块：
#
# 1. Network.ps1
#    - Test-NetworkConnectivity
#    - Get-FdDownloadUrl
#    - Download-FileParallel
#    - Download-Fd
#    - Ask-DownloadFd
#
# 2. Fallback.ps1
#    - Scan-Java-Fallback
#    - Invoke-FallbackScan
#
# 3. LightScan.ps1
#    - Scan-Java-Registry
#    - Scan-Java-MicrosoftStore
#    - Scan-Java-CommonPaths
#    - Scan-Java-Light
#
# 4. BFSScan.ps1
#    - Get-SearchRoots
#    - ShouldScanDirectory
#    - Scan-Java-BFS
#
# 5. FDScan.ps1
#    - Scan-Java-WithFD
#
# 所有模块会通过 src/core/Bootstrap.ps1 自动加载