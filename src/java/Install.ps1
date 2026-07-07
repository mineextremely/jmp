# src/java/Install.ps1
# JDK download and installation via Foojay Disco API

$Script:DiscoApiBase = "https://api.foojay.io/disco/v3.0"

# Map JMP vendor names to Foojay API distribution names
$Script:VendorToApiMap = @{
    "temurin"       = @("temurin")
    "zulu"          = @("zulu")
    "zulu_prime"    = @("zulu_prime")
    "liberica"      = @("liberica", "liberica_native")
    "oracle"             = @("oracle")
    "oracle_open_jdk"    = @("oracle_open_jdk")
    "corretto"           = @("corretto")
    "microsoft"          = @("microsoft")
    "graalvm"            = @("graalvm", "gluon_graalvm")
    "graalvm_community"  = @("graalvm_community", "graalvm_ce8", "graalvm_ce11", "graalvm_ce16", "graalvm_ce17", "graalvm_ce19", "graalvm_ce20")
    "dragonwell"    = @("dragonwell")
    "jetbrains"     = @("jetbrains")
    "semeru"        = @("semeru", "semeru_certified")
    "sap_machine"   = @("sap_machine")
    "kona"          = @("kona")
    "bisheng"       = @("bisheng")
    "redhat"        = @("redhat")
    "debian"        = @("debian")
    "mandrel"       = @("mandrel")
    "openlogic"     = @("openlogic")
    "trava"         = @("trava")
    "eliya"         = @("eliya")
    "aoj"           = @("aoj", "aoj_openj9")
    "ojdk_build"    = @("ojdk_build")
}

$Script:AvailableVersionsCache = $null

function Get-AvailableVersions {
    if ($Script:AvailableVersionsCache) {
        return $Script:AvailableVersionsCache
    }

    try {
        $response = Invoke-RestMethod -Uri "$Script:DiscoApiBase/major_versions" -ErrorAction Stop
        $versions = @{}
        foreach ($v in $response.result) {
            $key = [string]$v.major_version
            $versions[$key] = [pscustomobject]@{
                majorVersion     = $v.major_version
                termOfSupport    = $v.term_of_support
                maintained       = $v.maintained
                releaseStatus    = $v.release_status
                earlyAccessOnly  = $v.early_access_only
            }
        }
        $Script:AvailableVersionsCache = $versions
        return $versions
    } catch {
        if ($Global:JmpDebug) { Log-Debug "Failed to fetch major versions: $_" }
        return $null
    }
}

function Get-SystemArchitecture {
    if ([Environment]::Is64BitOperatingSystem) {
        try {
            $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
            if ($arch -eq [System.Runtime.InteropServices.Architecture]::Arm64) {
                return "arm64"
            }
        } catch {}
        return "x64"
    }
    return "x86"
}

function Get-ApiDistributionNames {
    param([string]$JmpVendor)

    if (-not $JmpVendor) { return @() }
    $vendorLower = $JmpVendor.ToLowerInvariant()

    if ($Script:VendorToApiMap.ContainsKey($vendorLower)) {
        $result = $Script:VendorToApiMap[$vendorLower]
        if ($Global:JmpDebug) { Log-Debug "VendorToApiMap['$vendorLower'] = [$($result -join ', ')]" }
        return $result
    }
    if ($Global:JmpDebug) { Log-Debug "Vendor '$vendorLower' not in map, using literal" }
    return @($vendorLower)
}

function Find-JavaPackage {
    param(
        [string]$Version,
        [string]$Vendor
    )

    $majorVersion = [string]$Version

    # Validate version exists and get metadata
    $allVersions = Get-AvailableVersions
    if ($allVersions -and -not $allVersions.ContainsKey($majorVersion)) {
        $available = ($allVersions.Keys | Sort-Object { [int]$_ }) -join ", "
        Write-Warning "Java $majorVersion is not available via Foojay Disco API."
        Write-Info "Available major versions: $available"
        return $null
    }
    $versionMeta = if ($allVersions) { $allVersions[$majorVersion] } else { $null }

    $arch = Get-SystemArchitecture

    $queryParams = @(
        "major_version=$majorVersion",
        "operating_system=windows",
        "architecture=$arch",
        "package_type=jdk",
        "archive_type=zip",
        "directly_downloadable=true",
        "release_status=ga"
    )
    # When vendor specified, use distro API filter for efficiency
    if ($Vendor) {
        $apiNames = @(Get-ApiDistributionNames -JmpVendor $Vendor)
        $distroValue = $apiNames[0]
        if ($Global:JmpDebug) { Log-Debug "distro API name: '$distroValue'" }
        $queryParams += "distro=$distroValue"
    }
    $queryString = $queryParams -join "&"
    $apiUrl = "$Script:DiscoApiBase/packages?$queryString"

    $supportLabel = ""
    if ($versionMeta) {
        $tosUpper = $versionMeta.termOfSupport.ToUpper()
        $maintLabel = if ($versionMeta.maintained) { "maintained" } else { "unmaintained" }
        $supportLabel = " ($tosUpper, $maintLabel)"
    }
    Write-Info "Querying Foojay Disco API for Java $majorVersion ($arch)$supportLabel..."
    if ($Global:JmpDebug) { Log-Debug "API URL: $apiUrl" }

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    } catch {
        Write-ErrorMsg "Failed to reach Foojay Disco API: $_"
        Write-Info "Check your network connection and try again."
        return $null
    }

    if (-not $response -or -not $response.result -or $response.result.Count -eq 0) {
        Write-Warning "No JDK packages found for Java $majorVersion on Windows $arch."
        return $null
    }

    if ($Global:JmpDebug) {
        Log-Debug "API returned $($response.result.Count) package(s)"
    }

    $allPackages = $response.result

    # Filter to exact major_version (API may return other versions)
    $packages = @($allPackages | Where-Object { $_.major_version -eq [int]$majorVersion })
    if ($Global:JmpDebug) {
        Log-Debug "API returned $($allPackages.Count) total, $($packages.Count) match major_version=$majorVersion"
    }

    # Dedup by distribution — keep the one with the highest distribution_version
    $deduped = @{}
    foreach ($pkg in $packages) {
        $dist = $pkg.distribution
        $ver = $pkg.distribution_version
        if (-not $deduped.ContainsKey($dist)) {
            $deduped[$dist] = $pkg
        } else {
            try {
                if ([System.Version]::Parse($ver) -gt [System.Version]::Parse($deduped[$dist].distribution_version)) {
                    $deduped[$dist] = $pkg
                }
            } catch {}
        }
    }
    $packages = @($deduped.Values)
    if ($Global:JmpDebug) {
        Log-Debug "After dedup by distribution: $($packages.Count) package(s)"
        foreach ($pkg in $packages) {
            Log-Debug "  $($pkg.distribution) version=$($pkg.distribution_version) java=$($pkg.java_version)"
        }
    }

    $match = $null
    $selectedVendor = $null

    if ($Vendor) {
        $apiNames = @(Get-ApiDistributionNames -JmpVendor $Vendor)
        if ($Global:JmpDebug) {
            Log-Debug "Looking for API distribution(s): $($apiNames -join ', ')"
        }
        foreach ($apiName in $apiNames) {
            $match = $packages | Where-Object { $_.distribution -eq $apiName } | Select-Object -First 1
            if ($match) {
                $selectedVendor = $Vendor
                break
            }
        }

        if (-not $match) {
            Write-Warning "Vendor '$Vendor' not available for Java $majorVersion."
            $available = $packages | ForEach-Object { $_.distribution } | Sort-Object -Unique
            Write-Info "Available distributions: $($available -join ', ')"
            Write-Info "Falling back to default vendor priority."
        }
    }

    if (-not $match) {
        foreach ($priorityVendor in Get-VendorPriority) {
            $apiNames = @(Get-ApiDistributionNames -JmpVendor $priorityVendor)
            foreach ($apiName in $apiNames) {
                $match = $packages | Where-Object { $_.distribution -eq $apiName } | Select-Object -First 1
                if ($match) {
                    $selectedVendor = $priorityVendor
                    if ($Global:JmpDebug) { Log-Debug "Selected vendor by priority: $priorityVendor ($($match.distribution))" }
                    break
                }
            }
            if ($match) { break }
        }
    }

    if (-not $match) {
        Write-ErrorMsg "No suitable JDK package found for Java $majorVersion."
        return $null
    }

    # Attach JMP vendor name and version metadata for downstream use
    $match | Add-Member -NotePropertyName "JmpVendor" -NotePropertyValue $selectedVendor -Force
    if ($versionMeta) {
        $match | Add-Member -NotePropertyName "VersionMeta" -NotePropertyValue $versionMeta -Force
    }

    $sizeMB = [Math]::Round($match.size / 1MB, 1)
    Write-Info "Selected: $selectedVendor $($match.java_version) ($sizeMB MB)"
    return $match
}

function Install-JavaPackage {
    param(
        $Package,
        [string]$InstallPath
    )

    if (-not $Package) {
        Write-ErrorMsg "No package provided for installation."
        return $false
    }

    $redirectUrl = $Package.links.pkg_download_redirect
    if (-not $redirectUrl) {
        Write-ErrorMsg "No download URL available for this package."
        return $false
    }

    $tempDir = Join-Path $env:TEMP "jmp-install-$([Guid]::NewGuid())"
    $zipFile = Join-Path $tempDir $Package.filename
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $sizeMB = [Math]::Round($Package.size / 1MB, 1)
        Write-Info "Downloading $($Package.filename) ($sizeMB MB)..."
        Write-Info "Source: $redirectUrl"

        Invoke-WebRequest -Uri $redirectUrl -OutFile $zipFile -ErrorAction Stop

        Write-Info "Extracting to $InstallPath..."
        if (Test-Path $InstallPath) {
            Remove-Item $InstallPath -Recurse -Force
        }
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null

        # Extract to temp location first to inspect structure
        $extractTemp = Join-Path $tempDir "_extracted"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractTemp)

        # Most JDK zips have a single top-level directory — flatten it
        $topItems = Get-ChildItem $extractTemp
        if ($topItems.Count -eq 1 -and $topItems[0].PSIsContainer) {
            # Move contents of the single top-level directory to InstallPath
            Get-ChildItem $topItems[0].FullName | Move-Item -Destination $InstallPath -Force
        } else {
            # Move everything directly
            $topItems | Move-Item -Destination $InstallPath -Force
        }

        Write-Success "Java $($Package.distribution) $($Package.java_version) installed to:"
        Write-Host "  $InstallPath" -ForegroundColor White

        return $true
    } catch {
        Write-ErrorMsg "Installation failed: $_"
        return $false
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
