# Release

- SemVer; `MARKETING_VERSION` in `project.yml`; tag `vX.Y.Z`; entry in `CHANGELOG.md`.
- CI (`.github/workflows/ci.yml`) runs `swift test` and an unsigned app build on each push and PR.
- No binary downloads yet: a notarized build needs a Developer ID certificate, which we don't have. Until then the README says to install from source.
