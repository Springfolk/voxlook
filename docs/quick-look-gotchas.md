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
- In zsh, `log` is a builtin; use `/usr/bin/log show|stream`.
