# Blind Soldier AMM v0.1.6 implementation plan

1. Change the catalog contract test to require two entries, no framework/runtime dependencies, v0.1.6 release records, hotkeys, and the new cleanup lifecycle declaration.
2. Run the test and confirm it fails against the current three-entry v0.1.3 catalog.
3. Extract the verified v0.1.6 portable release into isolated staging folders.
4. Keep the complete payload for `ffviinew`; create a whitelist-based x86-only payload for `ffviiold`.
5. Add the automatic legacy-registry cleanup wrapper and package README to both staging folders.
6. Use `amm-author` to remove `ffviioldsteam2026`, clear dependencies, update descriptions/lifecycle metadata, build both packages, and validate them.
7. Dry-run and then publish both v0.1.6 packages through `amm-author`.
8. Run the catalog contract, archive-content checks, hashes, Git status checks, and verify the published GitHub release and catalog.
