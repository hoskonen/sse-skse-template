# Initialization audit

Reproduced on Windows with Windows PowerShell 5.1, Git and XMake 3.0.9.
Testing used disposable clones; the template checkout's history was untouched.

## Before fixes

- A canonical `git clone --recurse-submodules` succeeded at template HEAD,
  with CommonLibSSE-NG `b9f1e9b4e4b102f95bb63590b0b31542c5d49747`
  and nested OpenVR `60eb187801956ad277f1cae6680e3a410ee0873b`.
- Running the original setup under PowerShell 5.1 stopped at
  `Run-Command git add -A`: `Missing an argument for parameter 'Arguments'`.
  PowerShell binds `-A` to the helper's `Arguments` parameter. Metadata had
  already been rewritten and HEAD was the unborn `project-main` branch.
  No initial commit was created. Retry then rejected the missing placeholder.
- Description `A "quoted" path C:\Mods` was inserted literally into the
  double-quoted Lua string, producing invalid Lua. The same description also
  feeds raw C++ and Windows resource strings in CommonLib's generator.
- README ended immediately after `cd MyPlugin`, inside an unclosed code fence,
  with no setup or build commands. Its `sse-skse-templte` URL is misspelled;
  GitHub currently redirects it, so this was not a reproduced clone failure.
- Git identity and XMake were checked only when needed, after edits/history
  changes. There was no recovery record for interrupted initialization.

The minimal plugin calls `SKSE::Init`, logs Hello World and returns success.
CommonLib's existing XMake rule generates plugin metadata. No plugin source,
dependency revision or runtime feature needs changing for these failures.

## Repairs

- Native commands receive explicit argument arrays and report their exit code.
- Validate names, generator-safe descriptions, standalone clone, branch layout,
  clean files, Git identity and gitlink before rewriting metadata. Initialize
  dependencies at their pinned revisions before saving project changes.
- Write metadata as UTF-8 with literal substitutions, including a project README
  containing both the name and description.
- Read recovery JSON explicitly as UTF-8 too: interruption testing with `cafe`
  ending in U+00E9 exposed PowerShell 5.1's legacy-code-page default for
  BOM-less `Get-Content`. This would falsely report additional metadata edits.
- Use `write-tree` / parentless `commit-tree` followed by a compare-and-swap
  `update-ref` of `main`, rather than switching to an unborn temporary branch.
  A recovery record in `.git` makes branch/remote finalization resumable and
  refuses unrelated edits. No template checkout history is changed by tests.
- Missing XMake warns after Git initialization; configuration errors return a
  useful command/exit code and can be retried without repeating initialization.
- XMake configuration explicitly selects the script's project directory. During
  testing in a dot-prefixed child directory, implicit discovery selected the
  parent template and reported missing CommonLib / invalid `--skyrim_vr`.
  Passing `-P` resolved this and configuration detected Visual Studio 2026.
  Setup also supplies the project's build directory explicitly.
- Complete README workflow, prerequisites, verification, recovery, deployment
  and smoke-test commands. Preserve `.gitmodules`, the minimal source, C++23,
  CommonLib's existing XMake rules and all dependency pins.
- Inspecting the compiled Windows version resource exposed another actual
  failure: a UTF-8 description ending in U+00E9 appeared as U+00C3 U+00A9 in
  the DLL. Set the target's Microsoft resource flags to `/c65001` with
  `force = true` (XMake's automatic probe otherwise ignored the valid flag), and assert
  the final DLL's exact FileDescription and ProductName in the build smoke test.

## Validation after repairs

- Windows PowerShell 5.1 parser checks passed for setup and the smoke script;
  `git diff --check` passed.
- Recursive GitHub clones succeeded. Repeated final tests used an already
  downloaded disposable fixture via `-RepositoryUrl`, with the current setup
  and README overlaid. Only disposable repositories received fixture commits
  or branch changes. Template HEAD remained `5094b72`.
- The smoke suite verified clean `main`, exactly one parentless initial commit,
  removed `origin`, unchanged stage-0 CommonLib gitlink, and initialized nested
  OpenVR after starting the generated clone without checked-out dependencies.
- Invalid names/descriptions, dirty source and invalid Git identity failed
  before metadata/history changes. Explicit empty inputs were also rejected.
- An injected `main.lock` failed branch finalization with an exit code and
  recovery record. Retry completed successfully, preserving Unicode metadata.
  Recovery also refused unrelated edits in a separate interrupted clone.
- Repeating setup preserved HEAD and clean files; attempting a rename was
  rejected. An injected XMake exit 17 preserved initialized Git history, and
  retry succeeded. Excluding XMake from PATH produced a clear warning and
  preserved HEAD.
- XMake 3.0.9 configured `releasedbg`, x64, SE/AE with VR disabled using Visual
  Studio 2026 and MSVC 14.51. Two real minimal DLL builds succeeded, including
  the smoke project's Unicode description, dollar sign and apostrophe. The
  first build took about 196 seconds. Existing unused-parameter warnings in
  CommonLib's trampoline implementation did not prevent the build.
- `dumpbin /exports` on the first DLL confirmed `SKSEPlugin_Load`,
  `SKSEPlugin_Query` and `SKSEPlugin_Version`. Builds left generated Git trees
  clean and deployment environment variables were cleared during the builds.
- The corrected resource was rebuilt and its actual `rc.exe` command included
  `/c65001`. The resulting DLL's FileDescription exactly matched the Unicode
  input, and ProductName was `SmokePlugin`; all SKSE exports were also confirmed
  on the smoke DLL. The final setup configured successfully when invoked from
  outside that disposable project. The final initialization suite, including
  explicit empty inputs and missing XMake, passed again in fresh disposable clones.

No Windows-tooling validation was blocked. In-game loading was outside this
template initialization/build audit and was not tested. No lockpicking mod
implementation was started.
