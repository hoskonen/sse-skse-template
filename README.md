# SKSE Plugin Template

Minimal reusable starter project for developing SKSE64 plugins with CommonLibSSE-NG and XMake.

The template provides a known-working baseline for:

- CommonLibSSE-NG
- C++23
- XMake builds
- SKSE plugin generation
- SE / AE development
- MO2 deployment through `XSE_TES5_MODS_PATH`
- Basic plugin logging
- Fresh project initialization through `setup.ps1`

The included plugin is intentionally minimal and can be used as a smoke test before starting actual development.

## Requirements

- Visual Studio with C++ development tools
- XMake
- SKSE64
- Address Library for SKSE Plugins
- Git

## Starting a New Plugin

Clone the template recursively:

```powershell
git clone --recurse-submodules https://github.com/hoskonen/sse-skse-templte.git MyPlugin
cd MyPlugin