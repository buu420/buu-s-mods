<#
.SYNOPSIS
Checks the Blind Soldier FFVII contract in the published catalog.

.PARAMETER ExpectedVersion
The release being verified. Without it this script only proves the two games agree with each
other - and they agree perfectly when a release is missing from both, which is the one thing a
release check must not be able to miss. Pass it after every publish.

.PARAMETER ExpectedChannel
The channel that release must be on. Defaults to beta, which is every release so far.

.NOTES
Run this after BOTH games have been published. Between the two publishes the catalog is
legitimately asymmetric, and this script is right to fail on it.
#>
param(
    [string]$ExpectedVersion,
    [string]$ExpectedChannel = 'beta'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function Test-DefinitionAtPath {
    param($Definition, [string]$Root)

    if ([string]::IsNullOrWhiteSpace([string]$Definition.exeName)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root $Definition.exeName) -PathType Leaf)) { return $false }

    foreach ($rule in @($Definition.probeRules)) {
        $path = Join-Path $Root $rule.relativePath
        $passes = switch ($rule.type) {
            'fileExists' { Test-Path -LiteralPath $path -PathType Leaf }
            'folderExists' { Test-Path -LiteralPath $path -PathType Container }
            default { $false }
        }
        if (-not $passes) { return $false }
    }
    return $true
}

function New-File {
    param([string]$Root, [string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllBytes($path, [byte[]]@(0))
}

$catalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'index.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$old = @($catalog.games | Where-Object gameId -eq 'ffviiold')
$new = @($catalog.games | Where-Object gameId -eq 'ffviinew')
$compat = @($catalog.games | Where-Object gameId -eq 'ffviioldsteam2026')
Assert-Equal 1 $old.Count 'The catalog must contain exactly one FFVII 2013 definition.'
Assert-Equal 1 $new.Count 'The catalog must contain exactly one FFVII 2026 definition.'
Assert-Equal 0 $compat.Count 'The separate 7th Heaven compatibility entry must be removed.'
Assert-Equal 2 @($catalog.games).Count 'The Blind Soldier catalog must contain only the supported 2013 and 2026 entries.'
$old = $old[0]
$new = $new[0]

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('amm-ff7-catalog-' + [Guid]::NewGuid().ToString('N'))
$oldFixture = Join-Path $tempRoot '2013'
$newFixture = Join-Path $tempRoot '2026'
$incompleteFixture = Join-Path $tempRoot 'incomplete'

try {
    New-Item -ItemType Directory -Path (Join-Path $oldFixture 'data') -Force | Out-Null
    New-File $oldFixture 'ff7_en.exe'
    New-File $oldFixture 'FF7_Launcher.exe'

    New-Item -ItemType Directory -Path (Join-Path $newFixture 'ff7\workingdir\data') -Force | Out-Null
    New-File $newFixture 'FFVII.exe'
    New-File $newFixture 'FFVII_LAUNCHER.exe'
    New-File $newFixture 'steam_api64.dll'
    New-File $newFixture 'ff7\resources\ff7_1.02\ff7_en'

    New-Item -ItemType Directory -Path $incompleteFixture -Force | Out-Null
    New-File $incompleteFixture 'FFVII.exe'

    Assert-True (Test-DefinitionAtPath $old $oldFixture) 'FFVII 2013 probes rejected a complete 2013 fixture.'
    Assert-True (-not (Test-DefinitionAtPath $old $newFixture)) 'FFVII 2013 probes accepted the 2026 layout.'
    Assert-True (Test-DefinitionAtPath $new $newFixture) 'FFVII 2026 probes rejected a complete 2026 fixture.'
    Assert-True (-not (Test-DefinitionAtPath $new $oldFixture)) 'FFVII 2026 probes accepted the 2013 layout.'
    Assert-True (-not (Test-DefinitionAtPath $old $incompleteFixture)) 'FFVII 2013 probes accepted an incomplete layout.'
    Assert-True (-not (Test-DefinitionAtPath $new $incompleteFixture)) 'FFVII 2026 probes accepted an incomplete layout.'

    foreach ($definition in @($old, $new)) {
        Assert-Equal 0 @($definition.dependencies).Count "$($definition.gameId) must be self-contained and dependency-free."
        Assert-True ($definition.description -match '## Hotkeys') "$($definition.gameId) description must contain the hotkey heading."
        foreach ($key in @('R', 'U', 'O', 'J', 'L', 'K', 'I', 'F5', 'F6', 'F7', 'F8', '1', '2', '3', 'H', 'M', 'D', 'S')) {
            $needle = [string]([char]96) + $key + [char]96
            Assert-True ($definition.description.Contains($needle)) "$($definition.gameId) description is missing hotkey $key."
        }

        $post = $definition.defaultPostInstall
        Assert-True ($null -ne $post) "$($definition.gameId) must declare the legacy-registry cleanup hook."
        Assert-Equal 'files/Blind-Soldier/Tools/Remove-AmethystRegistryEntries-Automatic.cmd' $post.executable "$($definition.gameId) has the wrong cleanup executable."
        Assert-True ([bool]$post.needsAdmin) "$($definition.gameId) cleanup must request elevation."
        Assert-True ([bool]$post.failureFatal) "$($definition.gameId) cleanup failure must abort the install."
        Assert-True ([bool]$post.runOnUpdate) "$($definition.gameId) cleanup must run on update."
        Assert-True (-not [bool]$post.installToGameFolder) "$($definition.gameId) must not retain a root-level cleanup script."
        Assert-True (-not [bool]$post.runFromGameFolder) "$($definition.gameId) cleanup should run from package staging."
    }

    $allDependencies = @($catalog.games | ForEach-Object { @($_.dependencies) })
    $mislabelled = @($allDependencies | Where-Object {
        $_.id -match 'seventh.?heaven' -and $_.fix.downloadUrl -match '/FFNx/'
    })
    Assert-Equal 0 $mislabelled.Count 'A dependency named for 7th Heaven still points to FFNx.'
    Assert-True ($catalog.releasesByGameId.PSObject.Properties.Name -notcontains 'ffviioldsteam2026') 'Release metadata for the removed 7th Heaven entry must also be removed.'

    # Which release this checks is read out of the catalog, never pinned. The pinned form went
    # stale the moment the next release shipped: it asserted 0.2.9 while 0.3.0, 0.3.1 and 0.4.0
    # came and went untested, and it would have printed "verified" for a catalog with the
    # release being published entirely absent. Pass -ExpectedVersion to nail down which release
    # is supposed to be there; the structural checks below hold either way.
    $byGame = @{}
    foreach ($gameId in @('ffviiold', 'ffviinew')) {
        $releases = @($catalog.releasesByGameId.$gameId)
        Assert-True ($releases.Count -gt 0) "$gameId publishes no releases at all."
        $byGame[$gameId] = $releases
    }

    # A release is identified by version AND channel: the same version on two channels is two
    # different downloads, and comparing versions alone would call them the same row.
    function Get-ReleaseIdentity {
        param($Release)
        return "$([string]$Release.version) ($([string]$Release.channel))"
    }

    # The invariant that matters most. Publishing the second game rebuilds the catalog from a
    # CDN-cached copy of the previous state and drops the row the first game just published -
    # 0.2.3, 0.2.8, 0.3.0, 0.3.1 and 0.4.0 each needed a repair commit. Both games ship the same
    # builds from the same tag, so their published releases must be identical and in the same
    # order. A publish abandoned after the first game fails here for the same reason.
    $oldIdentities = @($byGame['ffviiold'] | ForEach-Object { Get-ReleaseIdentity $_ })
    $newIdentities = @($byGame['ffviinew'] | ForEach-Object { Get-ReleaseIdentity $_ })
    $divergence = @(Compare-Object $oldIdentities $newIdentities -SyncWindow 0)
    Assert-True ($divergence.Count -eq 0) (
        'The two FFVII games publish different releases, so one of them lost an entry: ' +
        ((@($divergence | ForEach-Object {
            $side = if ($_.SideIndicator -eq '<=') { 'only in ffviiold' } else { 'only in ffviinew' }
            "$($_.InputObject) $side"
        })) -join '; ') + '.')

    # Every row, not only the newest. Several of these have been repaired by hand after a
    # clobber, and a hand-inserted row is exactly the kind that can name the other game's
    # package or a truncated digest while looking perfectly well formed.
    foreach ($gameId in @('ffviiold', 'ffviinew')) {
        $seen = @{}
        foreach ($release in $byGame[$gameId]) {
            $identity = Get-ReleaseIdentity $release
            Assert-True (-not $seen.ContainsKey($identity)) "$gameId publishes $identity more than once."
            $seen[$identity] = $true
            $version = [string]$release.version
            Assert-Equal $gameId $release.gameId "A release listed under $gameId names a different game."
            Assert-True ([string]$release.channel -match '^[a-z][a-z0-9]*$') "$gameId $version has no usable channel."
            Assert-True ($release.sha256 -match '^[0-9a-f]{64}$') "$gameId $version must have a SHA-256 digest."
            $expectedAsset = "/v$version/$gameId-v$version-amm.zip"
            Assert-True (([string]$release.packageUrl).EndsWith($expectedAsset)) `
                "$gameId $version points at '$($release.packageUrl)' instead of an asset ending '$expectedAsset'."
        }
    }

    # The release actually being verified. Matching lists alone cannot prove a release landed,
    # because two lists that both lost it still match.
    if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
        Write-Warning (
            "No -ExpectedVersion was given, so this run only proved the two games agree with " +
            "each other. Pass -ExpectedVersion to prove a particular release is published.")
    }
    else {
        $wanted = "$ExpectedVersion ($ExpectedChannel)"
        foreach ($gameId in @('ffviiold', 'ffviinew')) {
            $hits = @($byGame[$gameId] | Where-Object { (Get-ReleaseIdentity $_) -eq $wanted })
            Assert-Equal 1 $hits.Count "$gameId must publish exactly one $wanted release."
        }
    }

    $latest = $oldIdentities[-1]
    $summary = if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { "latest $latest" } else { "$ExpectedVersion ($ExpectedChannel) published, latest $latest" }
    Write-Host "FFVII catalog contract verified (both games publish $($oldIdentities.Count) releases, $summary)."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
