# Release

- SemVer; `MARKETING_VERSION` in `project.yml`; tag `vX.Y.Z`; entry in `CHANGELOG.md`.
- CI (`ci.yml`) runs `swift test` and an unsigned app build on each push and PR.
- Pushing a `v*` tag runs `release.yml`: tests, `make dist` (universal, ad-hoc signed `build/VoxLook.zip`), creates the release with that version's CHANGELOG section and uploads the zip. `install.sh` downloads `releases/latest/download/VoxLook.zip`.
- Not notarized (no Developer ID). That works because `curl` downloads aren't quarantined; browser downloads are.
