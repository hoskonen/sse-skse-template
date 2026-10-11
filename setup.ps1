[CmdletBinding()]
param(
    [string]$ProjectName,
    [string]$Description,
    [switch]$SkipConfigure
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# Pass native arguments as an explicit array: PowerShell otherwise binds -A/-m
# to this function's own parameters instead of passing them through to Git.
function Invoke-Native {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed (exit $LASTEXITCODE). See command output above."
    }
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Save-State {
    # Keep the last complete recovery record if writing is interrupted.
    Write-Utf8 "$script:statePath.tmp" ($script:state | ConvertTo-Json -Depth 4)
    if (Test-Path -LiteralPath $script:statePath) {
        [IO.File]::Replace("$script:statePath.tmp", $script:statePath, "$script:statePath.bak")
        Remove-Item -LiteralPath "$script:statePath.bak"
    } else {
        [IO.File]::Move("$script:statePath.tmp", $script:statePath)
    }
}

function Assert-Gitlink {
    $entry = Invoke-Native git @('ls-files', '--stage', '--', 'lib/commonlibsse-ng')
    if (($entry -join "`n") -notmatch '^160000 [0-9a-f]+ 0\s+lib/commonlibsse-ng$') {
        throw 'CommonLibSSE-NG is not registered as a stage-0 submodule gitlink.'
    }
}

$script:state = $null
$script:statePath = Join-Path $PSScriptRoot '.git/template-setup.json'
Push-Location $PSScriptRoot
try {
    Write-Host 'SKSE Plugin Template Setup'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is required. Install Git for Windows and reopen PowerShell.'
    }
    if (-not (Test-Path -LiteralPath '.git' -PathType Container)) {
        throw 'Use a standalone clone, not a linked worktree or source archive.'
    }
    $root = Invoke-Native git @('rev-parse', '--show-toplevel')
    if ([IO.Path]::GetFullPath($root) -ne [IO.Path]::GetFullPath($PSScriptRoot)) {
        throw 'setup.ps1 must belong to the root of the standalone clone.'
    }
    foreach ($file in @('xmake.lua', 'README.md', '.gitmodules', 'src/main.cpp')) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing required file: $file" }
    }
    $script:statePath = Join-Path $PSScriptRoot '.git/template-setup.json'
    $xmake = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'xmake.lua'))
    $script:state = $null

    if (Test-Path -LiteralPath $statePath) {
        $script:state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        if ($state.Version -ne 1) { throw 'Unsupported setup recovery record. Preserve .git/template-setup.json for diagnosis.' }
        if (($ProjectName -and $ProjectName -cne $state.ProjectName) -or
            ($Description -and $Description -cne $state.Description)) {
            throw 'An interrupted setup exists. Retry with the original metadata or omit the metadata parameters.'
        }
        Write-Host "Resuming interrupted setup for '$($state.ProjectName)'."
    } elseif ($xmake.Contains('__PROJECT_NAME__')) {
        if (-not $PSBoundParameters.ContainsKey('ProjectName')) { $ProjectName = Read-Host 'Project name' }
        if (-not $PSBoundParameters.ContainsKey('Description')) { $Description = Read-Host 'Description' }
        if ($ProjectName -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,63}$' -or
            $ProjectName -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            throw 'Project name must start with an ASCII letter, contain only letters, digits or underscores, and be at most 64 characters; Windows device names are reserved.'
        }
        if ([string]::IsNullOrWhiteSpace($Description) -or $Description -match '["\\\x00-\x1f\x7f]' -or
            $Description.Contains('__PROJECT_')) {
            throw 'Description must be non-empty, on one line, without double quotes, backslashes, control characters or template placeholders (CommonLib generates C++ and resource strings).'
        }
        if (-not $xmake.Contains('__PROJECT_DESCRIPTION__')) { throw 'Missing description placeholder in xmake.lua.' }
        $branch = Invoke-Native git @('symbolic-ref', '--short', 'HEAD')
        $branches = @(Invoke-Native git @('for-each-ref', '--format=%(refname:short)', 'refs/heads/'))
        if ($branch -ne 'main' -or $branches.Count -ne 1) {
            throw 'Initialize a fresh clone with only the main branch. Existing development branches will not be removed.'
        }
        if (Invoke-Native git @('status', '--porcelain')) { throw 'The clone must be clean before setup. Commit or remove local changes first.' }
        foreach ($operation in @('MERGE_HEAD', 'CHERRY_PICK_HEAD', 'rebase-merge', 'rebase-apply')) {
            if (Test-Path -LiteralPath (Join-Path '.git' $operation)) { throw "Finish the Git operation ($operation) before setup." }
        }
        # Fail before editing if a root commit cannot be authored.
        $null = Invoke-Native git @('var', 'GIT_AUTHOR_IDENT')
        $null = Invoke-Native git @('var', 'GIT_COMMITTER_IDENT')
        Assert-Gitlink
        Write-Host 'Initializing pinned submodules (network access may be required)...'
        Invoke-Native git @('submodule', 'update', '--init', '--recursive')
        if (Invoke-Native git @('status', '--porcelain')) { throw 'Submodules or working tree are dirty after dependency initialization.' }
        $readme = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'README.md'))
        $script:state = [pscustomobject]@{
            Version = 1
            ProjectName = $ProjectName
            Description = $Description
            OriginalHead = (Invoke-Native git @('rev-parse', 'HEAD'))
            RootCommit = ''
            OriginalXmake = $xmake
            OriginalReadme = $readme
            NewXmake = $xmake.Replace('__PROJECT_NAME__', $ProjectName).Replace('__PROJECT_DESCRIPTION__', $Description)
            NewReadme = "# $ProjectName`n`n$Description`n`n" +
                'Minimal SKSE plugin built with CommonLibSSE-NG, XMake and C++23. See [template instructions](https://github.com/hoskonen/sse-skse-template#readme) for prerequisites and build commands.' + "`n"
        }
        Save-State
    } else {
        if ($ProjectName -or $Description) { throw 'Already initialized; metadata parameters will not rename an existing project.' }
        Write-Host 'Project already initialized. Git history and metadata will not be changed.'
    }

    if ($null -ne $state) {
        $head = Invoke-Native git @('rev-parse', 'HEAD')
        if ($head -ne $state.OriginalHead -and $head -ne $state.RootCommit) {
            throw 'HEAD changed since setup started. Preserve the recovery record and inspect your Git history before retrying.'
        }
        if ((Invoke-Native git @('symbolic-ref', '--short', 'HEAD')) -ne 'main') { throw 'Return to main before resuming setup.' }
        # Never overwrite edits made after an interruption.
        foreach ($pair in @(@('xmake.lua', $state.OriginalXmake, $state.NewXmake), @('README.md', $state.OriginalReadme, $state.NewReadme))) {
            $content = [IO.File]::ReadAllText((Join-Path $PSScriptRoot $pair[0]))
            if ($content -cne $pair[1] -and $content -cne $pair[2]) { throw "Recovery stopped: $($pair[0]) has additional edits. Preserve those edits before retrying." }
        }
        $changed = @(Invoke-Native git @('status', '--porcelain'))
        foreach ($line in $changed) {
            if ($line -notmatch '^ [M] (README\.md|xmake\.lua)$|^[MA]  (README\.md|xmake\.lua)$|^MM (README\.md|xmake\.lua)$') {
                throw "Recovery stopped because another file changed: $line"
            }
        }
        Write-Utf8 (Join-Path $PSScriptRoot 'xmake.lua') $state.NewXmake
        Write-Utf8 (Join-Path $PSScriptRoot 'README.md') $state.NewReadme
        Invoke-Native git @('add', '--', 'xmake.lua', 'README.md')
        Assert-Gitlink
        if (-not $state.RootCommit) {
            $tree = Invoke-Native git @('write-tree')
            # No parent: prepare a root commit before changing any branch.
            $state.RootCommit = Invoke-Native git @('commit-tree', $tree, '-m', 'Initial project setup')
            Save-State
        }
        if ($head -eq $state.OriginalHead) {
            Invoke-Native git @('update-ref', 'refs/heads/main', $state.RootCommit, $state.OriginalHead)
        }
        if (@(Invoke-Native git @('remote')) -contains 'origin') { Invoke-Native git @('remote', 'remove', 'origin') }
        Assert-Gitlink
        if ((Invoke-Native git @('rev-list', '--count', 'HEAD')) -ne '1') { throw 'Expected exactly one initial root commit.' }
        if (Invoke-Native git @('status', '--porcelain')) { throw 'Expected a clean generated project.' }
        Remove-Item -LiteralPath $statePath
        Write-Host "Initialized '$($state.ProjectName)' on main with one root commit and no template origin."
    }

    if ($SkipConfigure) {
        Write-Host 'XMake configuration skipped. Run: xmake f -y -m releasedbg --skyrim_vr=n'
    } elseif (-not (Get-Command xmake -ErrorAction SilentlyContinue)) {
        Write-Warning 'Git initialization is complete, but XMake is unavailable. Install XMake >= 3.0.0 and Visual Studio C++ tools, then rerun setup.ps1 or configure manually.'
    } else {
        Write-Host 'Configuring XMake (may download and build packages)...'
        Invoke-Native xmake @('f', '-P', $PSScriptRoot, ('--builddir=' + (Join-Path $PSScriptRoot 'build')), '-y', '-m', 'releasedbg', '--skyrim_vr=n')
        Write-Host 'Configuration succeeded. Build with: xmake -y'
    }
} catch {
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($null -ne $state -and (Test-Path -LiteralPath $statePath)) {
        Write-Host 'Recovery record saved in .git/template-setup.json. Fix the reported problem and rerun setup.ps1 without metadata parameters.'
    } else {
        Write-Host 'Fix the reported problem and retry. If Git initialization completed, rerunning setup only retries configuration.'
    }
    throw
} finally {
    Pop-Location
}
