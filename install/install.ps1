# SlopOn installer for Windows x64 (Windows PowerShell 5.1 compatible).
#
#   powershell -NoProfile -c "irm https://slopon.dev/install.ps1 | iex"
#
# Downloads the latest release archive, verifies its SHA-256 against the
# GitHub release API asset digest, provisions a pinned Node 22 runtime under
# the install root when the system Node is missing or an unverified major,
# runs `npm ci` in backend\, creates a Start Menu shortcut, and puts the
# launcher dir on the user PATH so `slopon` works from any terminal. Per-user
# install: %LOCALAPPDATA%\Programs\SlopOn, no admin. ~/.slopon (config,
# database, attachments) is never touched.
#
# Environment overrides (CI / power users):
#   SLOPON_ARCHIVE=path|url   install from a local file (checksum SKIPPED for
#                             local paths) or an explicit URL (checksum verified)
#   SLOPON_GH_TOKEN=tok       GitHub API token (avoids anonymous rate limits)
#   SLOPON_SKIP_CHECKSUM=1    skip release-archive digest verification (CI only)
#
# The release archive is cached in ~\.slopon\cache and reused across runs when
# its SHA-256 matches the GitHub release API digest (skips the ~20 MB download).
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 can default to TLS 1.0 on older builds; everything
# we talk to (github.com, nodejs.org) requires TLS 1.2+.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = 'DigiDecode/SlopOn.dev'
$GhApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ReleasesUrl = "https://github.com/$Repo/releases"
$DefaultDlBase = "https://github.com/$Repo/releases/latest/download"
# Pinned on-demand runtime for machines without a verified Node 20/22.
# Update procedure: take the newest 22.x from https://nodejs.org/dist/index.json
# and mirror the change in install/install.sh (the pins must match).
$NodeVersion = '22.23.2'
$NodeDistBase = 'https://nodejs.org/dist'

function Fail($Message) {
    Write-Host "error: $Message" -ForegroundColor Red
    exit 1
}

function Warn($Message) {
    Write-Host "warning: $Message" -ForegroundColor Yellow
}

# ── 1. Gate: OS + CPU architecture ─────────────────────────────────────────
# Read the CPU's architecture, NOT the running process's environment: Windows
# PowerShell 5.1 on Windows 11 ARM64 is itself an x64-emulated process, so
# $env:PROCESSOR_ARCHITECTURE reports 'AMD64' there and would wrongly pass.
# Win32_Processor .Architecture: 9 = x64, 12 = ARM64.
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
if ($cpu.Architecture -ne 9) {
    Fail ("unsupported CPU architecture (Win32_Processor.Architecture = {0}; only x64 is supported). See {1}." -f $cpu.Architecture, $ReleasesUrl)
}

$Asset = 'slopon-windows-x64.zip'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'Programs\SlopOn'
$SloponHome = Join-Path $env:USERPROFILE '.slopon'
$ConfigFile = Join-Path $SloponHome 'config.json'
$PidFile = Join-Path $SloponHome 'backend.pid'

Write-Host "==> SlopOn installer: windows-x64 -> $InstallRoot"

# ── 2. Archive source + SHA-256 verification ───────────────────────────────
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("slopon-install-" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $Tmp | Out-Null

$ArchiveSrc = if ($env:SLOPON_ARCHIVE) { $env:SLOPON_ARCHIVE } else { "$DefaultDlBase/$Asset" }
$IsUrl = $ArchiveSrc -match '^https?://'

$Archive = $null
if (-not $IsUrl) {
    if (-not (Test-Path $ArchiveSrc)) { Fail "SLOPON_ARCHIVE file not found: $ArchiveSrc" }
    Write-Host "==> using local archive $ArchiveSrc (digest verification skipped by design for local files)"
    $Archive = (Resolve-Path $ArchiveSrc).Path
} elseif ($env:SLOPON_SKIP_CHECKSUM -eq '1') {
    Warn 'SLOPON_SKIP_CHECKSUM=1 - skipping archive digest verification (CI-only escape hatch)'
    Write-Host "==> downloading $Asset"
    $Archive = Join-Path $Tmp $Asset
    try {
        Invoke-WebRequest -Uri $ArchiveSrc -OutFile $Archive -UseBasicParsing
    } catch {
        Fail "download failed: $ArchiveSrc ($($_.Exception.Message))"
    }
} else {
    # The release archive is cached under ~\.slopon\cache so repeat installs
    # (upgrades) skip the ~20 MB CDN download. The GitHub API digest is
    # fetched FIRST - it is the reuse anchor for the cache and the
    # verification anchor for a fresh download; integrity is never skipped,
    # only satisfied early.
    $CacheDir = Join-Path $SloponHome 'cache'
    $CacheFile = Join-Path $CacheDir $Asset
    $DigestFile = "$CacheFile.sha256"
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    Write-Host '==> resolving the release digest from the GitHub release API'
    $Expected = $null
    $ApiFailure = $null
    try {
        $Headers = @{ Accept = 'application/vnd.github+json' }
        if ($env:SLOPON_GH_TOKEN) { $Headers['Authorization'] = "Bearer $($env:SLOPON_GH_TOKEN)" }
        $Release = Invoke-RestMethod -Uri $GhApiUrl -Headers $Headers
    } catch {
        $code = 0
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code -eq 403 -or $code -eq 429) {
            $ApiFailure = "GitHub API rate limit reached (HTTP $code) - retry in a while, or set SLOPON_GH_TOKEN to a token and re-run."
        } else {
            $ApiFailure = "GitHub release API request failed (HTTP $code) - cannot verify the archive digest."
        }
    }
    if (-not $ApiFailure) {
        foreach ($a in $Release.assets) {
            if ($a.name -eq $Asset) { $Expected = $a.digest; break }
        }
        if (-not $Expected) {
            Fail "the GitHub release API exposed no digest for '$Asset' - refusing to install unverified (API contract change?)."
        }
        $Expected = $Expected -replace '^sha256:', ''
    }
    $CacheHash = $null
    $StoredDigest = $null
    if (Test-Path $CacheFile) {
        $CacheHash = (Get-FileHash -Path $CacheFile -Algorithm SHA256).Hash.ToLowerInvariant()
        try { $StoredDigest = (Get-Content $DigestFile -ErrorAction Stop | Select-Object -First 1).Trim() } catch { $StoredDigest = $null }
    }
    if ($Expected -and $CacheHash -eq $Expected) {
        $Archive = $CacheFile
        Set-Content -Path $DigestFile -Value $Expected -Encoding ascii
        Write-Host "==> reusing cached release archive $CacheFile"
        Write-Host "    digest OK ($Expected)"
    } elseif (-not $Expected -and $CacheHash -and $StoredDigest -and $CacheHash -eq $StoredDigest) {
        # The sidecar digest was written only after a GitHub-verified
        # download, so the cache pair still chains to an attested digest -
        # reuse it with a loud warning instead of failing during an API outage.
        $Archive = $CacheFile
        Warn "GitHub API unreachable - reusing the previously verified cached archive ($ApiFailure)"
        Write-Host "    digest OK ($CacheHash)"
    } elseif (-not $Expected) {
        Fail $ApiFailure
    } else {
        Write-Host "==> downloading $Asset"
        $Partial = "$CacheFile.partial"
        try {
            Invoke-WebRequest -Uri $ArchiveSrc -OutFile $Partial -UseBasicParsing
        } catch {
            Fail "download failed: $ArchiveSrc ($($_.Exception.Message))"
        }
        $Actual = (Get-FileHash -Path $Partial -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($Actual -ne $Expected) {
            Remove-Item $Partial -Force -ErrorAction SilentlyContinue
            Fail "SHA-256 mismatch for $Asset (expected $Expected, got $Actual) - the download was corrupted or tampered with; not installing."
        }
        Move-Item -Path $Partial -Destination $CacheFile -Force
        Set-Content -Path $DigestFile -Value $Expected -Encoding ascii
        $Archive = $CacheFile
        Write-Host "    digest OK ($Actual)"
    }
}

# ── 3. Refuse to upgrade while SlopOn is running ───────────────────────────
if (Test-Path $PidFile) {
    $RunningPid = 0
    try { $RunningPid = [int](Get-Content $PidFile -ErrorAction Stop | Select-Object -First 1) } catch {}
    if ($RunningPid -gt 0 -and (Get-Process -Id $RunningPid -ErrorAction SilentlyContinue)) {
        Fail ("the SlopOn backend (PID {0}) is running.`n         Stop it first:  taskkill /PID {0} /T`n         (or run `"{1}\launcher\slopon.cmd`" --stop)`n         then re-run the installer." -f $RunningPid, $InstallRoot)
    }
}
if (Test-Path $ConfigFile) {
    try { $Cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json } catch { $Cfg = $null }
    if ($Cfg -and $Cfg.server -and $Cfg.server.port) {
        $ProbeIp = '127.0.0.1'
        if ($Cfg.server.listenIp -and $Cfg.server.listenIp -ne '0.0.0.0' -and $Cfg.server.listenIp -ne '::') {
            $ProbeIp = $Cfg.server.listenIp
        }
        $Tcp = New-Object Net.Sockets.TcpClient
        try {
            $Connect = $Tcp.BeginConnect($ProbeIp, [int]$Cfg.server.port, $null, $null)
            if ($Connect.AsyncWaitHandle.WaitOne(1500) -and $Tcp.Connected) {
                Fail ("something is listening on {0}:{1} (the backend was likely started manually).`n         Stop it first (taskkill or the launcher --stop helper),`n         then re-run the installer." -f $ProbeIp, $Cfg.server.port)
            }
        } catch {
        } finally { $Tcp.Close() }
    }
}
if (Get-Process -Name 'slopon_dev' -ErrorAction SilentlyContinue) {
    Fail "the SlopOn app (slopon_dev) is running.`n         Close the SlopOn app, then re-run the installer."
}

# ── 4. Node runtime: system Node 20/22, else a pinned bundled Node 22 ─────
$NodeKind = $null
$NodeBin = $null
$SysNodeVersion = $null
try { $SysNodeVersion = (& node --version) 2>$null } catch {}
if ($SysNodeVersion -and ($SysNodeVersion -match '^v(20|22)\.')) {
    $NodeKind = 'system'
    Write-Host "==> using system Node $SysNodeVersion"
} elseif ($SysNodeVersion) {
    Write-Host "==> system Node $SysNodeVersion is not a verified major (20/22) - using bundled Node $NodeVersion"
} else {
    Write-Host "==> Node not found on PATH - will provision bundled Node $NodeVersion"
}

# A bundled runtime left by a previous run is reused when it matches the pin -
# nodeless machines must not re-download on every installer run. A mismatch
# (pin bump) or a broken binary falls through to the download, which replaces it.
if (-not $NodeKind -and (Test-Path (Join-Path $InstallRoot 'node-runtime\node.exe'))) {
    $BundledBin = Join-Path $InstallRoot 'node-runtime\node.exe'
    $BundledVersion = $null
    try { $BundledVersion = (& $BundledBin --version) 2>$null } catch {}
    if ($BundledVersion -eq "v$NodeVersion") {
        $NodeBin = $BundledBin
        Write-Host "==> reusing bundled Node $BundledVersion at $(Join-Path $InstallRoot 'node-runtime')"
    } else {
        $BundledState = if ($BundledVersion) { $BundledVersion } else { 'broken' }
        Write-Host "==> bundled Node is $BundledState - re-downloading v$NodeVersion"
    }
}

if (-not $NodeKind -and -not $NodeBin) {
    # Official asset names AND the dist directory carry a leading "v"
    # (https://nodejs.org/dist/v22.23.2/node-v22.23.2-win-x64.zip).
    $NodeFile = "node-v$NodeVersion-win-x64.zip"
    Write-Host "==> downloading $NodeFile"
    $NodeZip = Join-Path $Tmp $NodeFile
    try {
        Invoke-WebRequest -Uri "$NodeDistBase/v$NodeVersion/$NodeFile" -OutFile $NodeZip -UseBasicParsing
    } catch {
        Fail "Node runtime download failed: $($_.Exception.Message)"
    }
    $SumsFile = Join-Path $Tmp 'SHASUMS256.txt'
    try {
        Invoke-WebRequest -Uri "$NodeDistBase/v$NodeVersion/SHASUMS256.txt" -OutFile $SumsFile -UseBasicParsing
    } catch {
        Fail "could not download SHASUMS256.txt for Node $NodeVersion"
    }
    $NodeExpected = $null
    foreach ($line in (Get-Content $SumsFile)) {
        if ($line -match ('^\s*([0-9a-f]{64})\s+\*?' + [Regex]::Escape($NodeFile) + '\s*$')) {
            $NodeExpected = $Matches[1]
            break
        }
    }
    if (-not $NodeExpected) { Fail "$NodeFile not listed in SHASUMS256.txt" }
    $NodeActual = (Get-FileHash -Path $NodeZip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($NodeActual -ne $NodeExpected) {
        Fail "Node runtime SHA-256 mismatch (expected $NodeExpected, got $NodeActual)"
    }
    Write-Host "    digest OK ($NodeActual)"
    $RuntimeDir = Join-Path $InstallRoot 'node-runtime'
    if (Test-Path $RuntimeDir) { Remove-Item $RuntimeDir -Recurse -Force }
    New-Item -ItemType Directory -Path $RuntimeDir | Out-Null
    # The zip was downloaded by Invoke-WebRequest, so every extracted file
    # carries the Mark-of-the-Web; Unblock-File just deletes the
    # Zone.Identifier stream so the runtime is not SmartScreen-gated.
    $Unpack = Join-Path $Tmp 'node-unpack'
    Expand-Archive -Path $NodeZip -DestinationPath $Unpack -Force
    Get-ChildItem -Path $Unpack -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
    $Wrapped = Get-ChildItem -Path $Unpack -Directory | Select-Object -First 1
    if (-not $Wrapped) { Fail 'Node zip did not wrap the expected top-level directory' }
    Move-Item -Path (Join-Path $Wrapped.FullName '*') -Destination $RuntimeDir
    $NodeBin = Join-Path $RuntimeDir 'node.exe'
    if (-not (Test-Path $NodeBin)) { Fail "node.exe not found after extraction ($NodeBin)" }
    Write-Host "    bundled runtime installed at $RuntimeDir"
}

# npm resolution: bundled runtime ships npm.cmd next to node.exe; system Node
# resolves npm from PATH. Preferred invocation is npm-cli.js run through node
# directly — a bare `npm` on Windows can resolve through version-manager or
# corepack shims that forward differently per shell.
$NpmCmd = $null   # single .cmd/.exe path — fallback invocation
$NpmCli = $null   # node_modules\npm\bin\npm-cli.js — preferred
$NodeExe = $NodeBin
if ($NodeBin) {
    $NpmCmd = Join-Path (Split-Path $NodeBin) 'npm.cmd'
    if (-not (Test-Path $NpmCmd)) { Fail "npm not found next to the bundled Node ($NpmCmd)" }
} else {
    # -CommandType Application keeps aliases/functions/ps1 scripts out. With
    # more than one npm on PATH (version-manager shim dirs ship npm.ps1 AND
    # npm.cmd), .Source member-enumerates into an ARRAY and the call operator
    # then splats it into command + bogus arguments — observed in the wild as
    # npm answering 'Unknown command: "NpmCmd"'. Always pick exactly one real
    # executable.
    $NpmCmd = @((Get-Command npm -CommandType Application -ErrorAction SilentlyContinue)) |
        ForEach-Object { $_.Source } |
        Where-Object { $_ -and ($_ -match '\.(cmd|exe)$') } |
        Select-Object -First 1
    if (-not $NpmCmd) { Fail 'npm not found on PATH (system Node without npm?)' }
    $NodeExe = @((Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue)) |
        Select-Object -First 1 -ExpandProperty Source
}
if ($NodeExe) {
    $candidate = Join-Path (Split-Path $NodeExe) 'node_modules\npm\bin\npm-cli.js'
    if (Test-Path $candidate) { $NpmCli = $candidate }
}

# ── 5. git (warning only) ──────────────────────────────────────────────────
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host '==> git: found'
} else {
    Warn 'git is not installed - installation continues, but backend features that shell out to git will fail at runtime. Install git (e.g. winget install Git.Git) for full functionality.'
}

# ── 6. Extract + all-or-nothing file replacement ──────────────────────────
Write-Host '==> extracting release payload'
$ExtractDir = Join-Path $Tmp 'extract'
Expand-Archive -Path $Archive -DestinationPath $ExtractDir -Force
# The archive was downloaded by Invoke-WebRequest, so every extracted file
# carries the Mark-of-the-Web; SmartScreen can then silently block the
# unsigned GUI exe when the launcher (or the user) starts it.
# Unblock-File just deletes the Zone.Identifier stream.
Get-ChildItem -Path $ExtractDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
$Payload = Get-ChildItem -Path $ExtractDir -Directory | Select-Object -First 1
if (-not $Payload) { Fail 'archive does not wrap a top-level slopon-<platform>\ directory' }
foreach ($Dir in 'frontend', 'backend', 'launcher') {
    if (-not (Test-Path (Join-Path $Payload.FullName $Dir))) {
        Fail "archive payload is missing '$Dir'"
    }
}

Write-Host "==> installing app files into $InstallRoot"
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
# All moves-aside happen first, then all move-ins; any failure restores the
# aside dirs so a mid-upgrade failure never leaves a mixed-version install.
$Aside = Join-Path $Tmp 'aside'
New-Item -ItemType Directory -Path $Aside | Out-Null
$MovedAside = @()
foreach ($Dir in 'frontend', 'backend', 'launcher') {
    $Target = Join-Path $InstallRoot $Dir
    if (Test-Path $Target) {
        Move-Item -Path $Target -Destination (Join-Path $Aside $Dir)
        $MovedAside += $Dir
    }
}
try {
    foreach ($Dir in 'frontend', 'backend', 'launcher') {
        Move-Item -Path (Join-Path $Payload.FullName $Dir) -Destination (Join-Path $InstallRoot $Dir)
    }
} catch {
    foreach ($Dir in $MovedAside) {
        $Target = Join-Path $InstallRoot $Dir
        if (Test-Path $Target) { Remove-Item $Target -Recurse -Force }
        Move-Item -Path (Join-Path $Aside $Dir) -Destination $Target
    }
    Fail "moving new files into place failed - previous version restored (no partial install)."
}

# ── 7. Backend dependencies (lockfile-driven) ──────────────────────────────
Write-Host '==> installing backend dependencies (npm ci)'
$BackendDir = Join-Path $InstallRoot 'backend'
try {
    Push-Location $BackendDir
    if ($NodeBin) {
        # Keep the bundled runtime first on PATH so npm-cli.js resolves its
        # own node.exe and any spawned shims use the same runtime.
        $env:PATH = "$(Split-Path $NodeBin);$($env:PATH)"
    }
    if ($NpmCli) {
        # Direct npm-cli.js via node — immune to npm shims on PATH.
        & $NodeExe $NpmCli ci --no-audit --no-fund
    } else {
        & $NpmCmd ci --no-audit --no-fund
    }
    if ($LASTEXITCODE -ne 0) { throw 'npm ci exited non-zero' }
} catch {
    Fail "npm ci failed - see the output above; your install files are in place but the backend has no dependencies yet."
} finally {
    Pop-Location
}

# ── 8. Start Menu shortcut ─────────────────────────────────────────────────
$LnkPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\SlopOn.lnk'
Write-Host "==> creating shortcut $LnkPath"
$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($LnkPath)
$Shortcut.TargetPath = Join-Path $InstallRoot 'launcher\slopon.cmd'
$Shortcut.WorkingDirectory = $InstallRoot
# 7 = Minimized: the launcher console exists only for the readiness wait.
$Shortcut.WindowStyle = 7
$Shortcut.IconLocation = Join-Path $InstallRoot 'frontend\slopon_dev.exe'
$Shortcut.Description = 'SlopOn - agentic coding environment'
$Shortcut.Save()

# ── 8b. `slopon` command on the user PATH ──────────────────────────────
# Adds <install>\launcher to the USER Path (HKCU, no admin), so typing
# `slopon` (slopon.cmd; .CMD is in PATHEXT) works from any terminal. The RAW
# registry value is read/written (DoNotExpandEnvironmentNames) so %VAR%
# entries other installers left in the user PATH survive un-expanded.
$LauncherDir = Join-Path $InstallRoot 'launcher'
Write-Host "==> adding $LauncherDir to the user PATH (slopon command)"
try {
    $EnvKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $RawPath = [string]$EnvKey.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $OnPath = $false
    foreach ($Entry in ($RawPath -split ';')) {
        if ($Entry -and ($Entry.Trim() -ieq $LauncherDir)) { $OnPath = $true; break }
    }
    if (-not $OnPath) {
        $NewPath = if ($RawPath.Trim()) { "$RawPath;$LauncherDir" } else { $LauncherDir }
        # ExpandString keeps any existing %USERPROFILE%\... entries functional.
        $EnvKey.SetValue('Path', $NewPath, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
    $EnvKey.Close()
} catch {
    Warn "could not update the user PATH ($($_.Exception.Message)) - start via the Start Menu shortcut instead."
}
# The registry only affects processes started later; make `slopon` work in
# THIS window right away (matters for the `irm | iex` one-liner flow).
$env:Path = "$LauncherDir;$env:Path"
# Broadcast WM_SETTINGCHANGE so Explorer (and terminals launched from it)
# pick up the new PATH without a logoff. Best-effort.
try {
    Add-Type -Namespace SlopOnInstaller -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    $Result = [UIntPtr]::Zero
    [void][SlopOnInstaller.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$Result)
} catch {
}

# ── 9. Summary ─────────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'SlopOn installed successfully.'
Write-Host "  Install home : $InstallRoot"
Write-Host '  Start        : type `slopon` in a NEW terminal, or SlopOn (Start Menu).'
Write-Host "                 A terminal that is already open cannot pick this up (a child"
Write-Host "                 process cannot modify its parent's PATH). To use it in the"
Write-Host "                 terminal that ran this installer, paste:"
Write-Host "                   `$env:Path += ';$(Join-Path $InstallRoot 'launcher')'""
Write-Host "                 direct: $(Join-Path $InstallRoot 'launcher\slopon.cmd')"
Write-Host "  Stop backend : `"$(Join-Path $InstallRoot 'launcher\slopon.cmd')`" --stop  (best-effort hard kill)"
Write-Host "  Logs         : $(Join-Path $SloponHome 'logs\backend.log') and launcher.log"
if ($NodeKind -ne 'system') {
    Write-Host "  Node runtime : bundled $NodeVersion at $(Join-Path $InstallRoot 'node-runtime')"
}
Write-Host "  Data (~/.slopon - kept untouched across upgrades): $SloponHome"
Write-Host '  Upgrade      : re-run this installer with SlopOn stopped.'

Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue
