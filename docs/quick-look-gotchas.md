# Quick Look gotchas

- **Don't conform the UTI to `public.3d-content`.** Apple's `SceneKitQLThumbnailExtension` claims that type and wins; thumbnails fail with `QLThumbnailErrorDomain` 102.
- **ThumbnailsAgent caches which extension handles a type.** After changing UTIs or extensions, `qlmanage -r` isn't enough; `pkill -9 -f com.apple.quicklook.ThumbnailsAgent` (launchd restarts it; `kickstart` is SIP-blocked).
- **Finder keeps its own icon cache.** Files it saw before the extension worked keep a plain icon until Finder relaunches (`killall Finder`); `install.sh` does this.
- **A file's plain icon comes from its default app.** Media players like IINA claim `.vox` as audio (Dialogic VOX), so their AUDIO icon wins over `VoxDocument.icns`. Thumbnails cover it; we don't change the user's default app.
- **No public API removes Finder's white tile** behind document thumbnails.
- **`qlmanage -t` hangs** for app-extension thumbnails here; test with `QLThumbnailGenerator` instead (e.g. a 20-line Swift script).
- **`QLThumbnailReply(contextSize:drawing:)`** hands a pixel-sized `CGContext` with no scale transform: draw into `context.width × context.height`.
- **SceneKit byte colours aren't normalised.** A `UInt8` `.color` source reads as 0–255 → everything saturates; use floats.
- **XcodeGen overwrites entitlement files**: list the keys under `entitlements.properties` in `project.yml`.
- **SceneKit takes half floats** (`bytesPerComponent: 2`, float components): pixel-identical, half the memory.
- In zsh, `log` is a builtin; use `/usr/bin/log show|stream`.

## Spotlight

- **`CSImportExtension` (`com.apple.spotlight.import`) is a no-op on macOS** (Apple docs + DTS); it registers but `update` is never called. Use a classic `.mdimporter` in `Contents/Library/Spotlight`.
- **XcodeGen `bundle` targets get no `CFBundleExecutable`**; without it the importer silently never loads. It's set in `project.yml`.
- **`mdimport -t -d2 file.vox`** tests it ("with plugIn …" + attributes); **`mdimport -L`** lists known importers.
- **mds didn't discover the app-embedded importer** (waited 10+ min, fresh bundle ID, app launched). A symlink in `~/Library/Spotlight` + `mdimport -r` is picked up at once and resolves to the app's copy; `install.sh` makes it, `--uninstall` removes it.
- **mds caches importer paths** (one per bundle ID, kept after the file's deleted). Two registered copies of the app (e.g. the Xcode build product) can win over `/Applications`; `make install`/`make dist` unregister their build products.
