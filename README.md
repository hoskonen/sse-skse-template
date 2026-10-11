# SKSE Plugin Template

Minimal SKSE64 plugin using CommonLibSSE-NG, XMake and C++23. The plugin initializes
SKSE, logs `Hello World!` and returns success. CommonLib's XMake rule generates
the SKSE metadata and Windows version resource.

## Prerequisites

- Git for Windows, with a configured commit name and email.
- Windows PowerShell 5.1 or newer.
- XMake **3.0.0 or newer** (required by the pinned CommonLib revision).
- Visual Studio 2022 or newer with **Desktop development with C++**, MSVC x64
  tools and a Windows SDK. Use a recent toolset with C++23 support.
- Internet access for submodules and XMake's package downloads on first build.

SKSE64 and the appropriate Address Library for SKSE Plugins are needed to run
the DLL in Skyrim SE/AE; they are not needed to compile it.

## Starting a new plugin

Use a fresh, standalone clone. Initialization replaces the clone's `main` history
with one root commit and removes its template `origin`. Do not initialize a clone
containing existing development work. Other local branches and dirty files are
rejected instead of removed. Dependency versions remain pinned to the gitlinks;
setup does not use `git submodule update --remote`.

```powershell
git clone --recurse-submodules https://github.com/hoskonen/sse-skse-template.git MyPlugin
cd MyPlugin
# Set these locally if you have not configured a Git identity already:
git config user.name "Your Name"
git config user.email "you@example.com"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -ProjectName MyPlugin -Description "My minimal SKSE plugin"
xmake -y
```

Without metadata parameters, setup prompts for the name and description. Names
start with an ASCII letter and contain only letters, digits and underscores (up
to 64 characters); Windows device names are reserved. Descriptions must be
non-empty, on one line, without double quotes, backslashes, control characters or
template placeholders. CommonLib inserts this text into C++ and Windows resource
strings, so those characters cannot safely be passed through its current rule.
Metadata is written as UTF-8. The generated README contains your name and description.
The Windows resource compiler also uses UTF-8 so non-ASCII descriptions survive
in the DLL's version information.

Setup runs from its own directory, even when invoked from another directory.
It initializes missing submodules, checks Git identity and the clean tree before
editing metadata, and creates a root commit before changing `main`. Interrupted
initialization saves `.git/template-setup.json`; fix the reported error and rerun
without metadata parameters. Recovery refuses to overwrite additional edits.
Keep the recovery record until setup completes. Do not run two setups concurrently.

Git initialization and build configuration are separate steps. Missing XMake
produces a warning after Git initialization succeeds. A failed configuration
returns an error with the command and exit code; the initialized project remains
usable. After installing/fixing build prerequisites, rerun setup without metadata
parameters to retry configuration. Repeating setup never resets initialized history.
To initialize without configuring, add `-SkipConfigure`.

Configure manually if needed:

```powershell
git submodule update --init --recursive
xmake f -y -m releasedbg --skyrim_vr=n
xmake -y
```

`releasedbg` builds SE/AE support with debug symbols and disables VR. XMake can
find an installed Visual Studio toolchain even when `cl.exe` is not on PATH.
The DLL and PDB are normally in `build/windows/x64/releasedbg/`.

Verify the generated repository:

```powershell
git branch --show-current                 # main
git rev-list --count HEAD                  # 1
git rev-list --parents HEAD                # one hash, no parent hash
git status --short                        # empty
git remote -v                             # empty for the documented clone
git ls-files --stage lib/commonlibsse-ng   # starts with 160000
git submodule status --recursive          # initialized pinned revisions
```

Create an empty remote repository and attach it only after successful setup:

```powershell
git remote add origin https://github.com/YOUR-ACCOUNT/MyPlugin.git
git push -u origin main
```

## Deployment

For automatic MO2 deployment, set `XSE_TES5_MODS_PATH` to your MO2 `mods` directory
before configuring/building. CommonLib installs into a mod named after the target,
under `SKSE/Plugins`. Alternatively set `XSE_TES5_GAME_PATH` to the Skyrim directory
for direct installation. Leave both unset for an isolated smoke build. Install the
matching SKSE64 and Address Library before testing in the game.

## Repeatable validation

From the template checkout, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
# Also configure and build when the Windows C++ toolchain is available:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1 -Build
```

The smoke test recursively clones the canonical URL into a temporary directory,
overlays the current setup/README/XMake files for testing, and commits that fixture locally.
All history changes occur inside disposable clones. It checks metadata,
submodule registration, root history, retry behavior, invalid inputs, dirty files,
missing Git identity, missing XMake, configuration errors and interruption recovery. It retains temporary clones and
prints their location for inspection. `-Build` also configures and builds a real
DLL without deployment environment variables. No new runtime dependencies are used.
For subsequent runs, `-RepositoryUrl C:\path\to\an\existing\clone` can reuse a
previously downloaded template as the clone source; tests still create disposable
clones and overlay the current setup/README/XMake files. The default always uses GitHub.

See [AUDIT.md](AUDIT.md) for reproduced failures, fixes and validation results.
