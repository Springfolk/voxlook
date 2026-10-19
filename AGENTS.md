# VoxLook

Quick Look preview + thumbnail extensions for MagicaVoxel `.vox` on macOS 14+. Public MIT repo `Springfolk/voxlook`.

- `make test` — `swift test` (parser, mesher, scene graph, offscreen render).
- `make install` — XcodeGen → xcodebuild → `install.sh --from <app>` (registers extensions, resets QL caches, relaunches Finder).
- `make dist` — universal ad-hoc `build/VoxLook.zip`; tagging `v*` publishes it via `release.yml`. Users install with the `install.sh` curl one-liner.
- `swift run -c release voxthumb in.vox out.png 512` — render without installing.
- `VoxLook.xcodeproj`, the Info.plists and `Config/Sandbox.entitlements` are generated from `project.yml`; edit that.
- Keep it power-frugal: no render loops, shadows or post-processing; mesh once per model.
- Never commit third-party `.vox` files; fixtures are built in code (`Tests/VoxKitTests/VoxWriter.swift`), samples by `scripts/make-samples.py`.

## docs/

- `docs/architecture.md` — targets, data flow, where each piece lives.
- `docs/vox-format.md` — format details we rely on, coordinate conventions.
- `docs/quick-look-gotchas.md` — macOS pitfalls hit while building (UTI, caches, SceneKit).
- `docs/release.md` — versioning, CHANGELOG, what a release needs.
