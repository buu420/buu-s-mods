# Blind Soldier AMM v0.1.6 package design

## Goal

Replace the three existing Blind Soldier catalog choices with two supported v0.1.6 choices without changing Accessibility Mod Manager itself.

## Catalog shape

- `ffviinew`: Final Fantasy VII 2026. Ships the complete v0.1.6 portable package so the accessible launcher, x64 runtime, x86 compatibility runtime, Reloaded components, tools, and documentation are all present.
- `ffviiold`: Final Fantasy VII 2013. Ships only the x86 bootstrap/private runtime, x86 Reloaded loader and hooks, shared accessibility assets, the legacy `version.dll` proxy, cleanup tooling, licenses, and documentation.
- Remove `ffviioldsteam2026`. Blind Soldier must not advertise or install 7th Heaven or FFNx through the catalog.

Both supported entries have no external .NET dependency because the private runtime is bundled.

## Upgrade behavior

The old manager packages invoked `BlindSoldier_Installer.exe`, which could leave Blind Soldier Image File Execution Options launch values outside the manager's file receipt. The v0.1.6 packages use their native proxy bootstrap instead. A post-install wrapper therefore runs the bundled targeted cleanup script on both initial install and update. It removes only Blind Soldier-owned legacy values and preserves unrelated debugger values. The wrapper runs from package staging and is not retained as a root-level game file.

All ordinary files are replaced through the manager's normal package transaction. No mod-manager code is changed.

## User-facing information

Both catalog descriptions follow Amethyst's Markdown pattern: a short explanation, supported runtime, navigation overview, and the complete hotkey list. Each package also includes a matching readable README.

## Verification

- Catalog contract test requires exactly the two supported game entries.
- Package validation checks identity, version, manifests, SHA-256 values, lifecycle script, and forbidden dependencies/files.
- Archive-content checks prove the 2026 package is complete and the 2013 package contains no x64, accessible-launcher, FFNx, 7th Heaven, or working-directory payload.
