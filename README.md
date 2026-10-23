<p align="center"><img src="docs/icon.png" width="128" alt="VoxLook icon"></p>

<h1 align="center">VoxLook</h1>

<p align="center">Quick Look for MagicaVoxel <code>.vox</code> files on macOS.<br>
Finder thumbnails, and a 3D preview you can spin when you press Space.</p>

<p align="center"><img src="docs/samples.png" alt="Thumbnails of three sample models"></p>

## What it does

- **Thumbnails.** Finder icons, column view and Get Info show the model itself, not a blank document.
- **Space-bar preview.** An orbitable 3D view with the model's size, voxel count and palette. Drag to turn it, scroll or pinch to zoom, double-click to reset. Animated files get a play button; files with layers get a menu to show or hide each one, hidden layers included.
- **Shading and materials.** Corners and creases get ambient occlusion. Emissive voxels glow, metal has a highlight, and glass is see-through.
- **Spotlight.** Finds `.vox` files by object and layer names and shows their size and voxel count as the description.
- **Whole scenes.** It reads MagicaVoxel's scene graph: multiple models, groups, rotations, mirroring and the palette. Hidden layers and hidden objects are left out.
- **Light on the battery.** The preview redraws only while you drag it or play an animation, and uses no CPU while it sits open. Thumbnails render on the low-power GPU, and Quick Look caches them. Ambient occlusion is baked in when a model is meshed, so drawing costs nothing extra. Rendering 93 real-world files takes 0.7 s of CPU in total (`voxthumb --bench`). Models are greedy-meshed, with only their occupied voxels stored, and each model is meshed once however many times it's placed.
- **Sandboxed.** The Quick Look extensions only read the file they're given.

Requires macOS 14 or later.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Springfolk/voxlook/main/install.sh | bash
```

This downloads the latest release (universal, ~1.4 MB) into `/Applications`, or `~/Applications` if you can't write there. It registers the extensions and the Spotlight importer (linked from `~/Library/Spotlight`), clears Quick Look's caches and relaunches Finder so files that already had a plain icon pick up their thumbnails. Run it again to update. To remove VoxLook:

```sh
curl -fsSL https://raw.githubusercontent.com/Springfolk/voxlook/main/install.sh | bash -s -- --uninstall
```

The download is signed ad hoc, not notarized. It runs because `curl` doesn't quarantine files the way a browser does, so a `VoxLook.zip` you open from a browser download will be blocked by Gatekeeper.

### From source

You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). `make install` builds the app and installs it through the same script; `make uninstall` removes it. To sign with your own team instead of ad hoc, create `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Automatic
```

## Command line

`voxthumb` renders any `.vox` to a PNG through the same code path as the Finder thumbnails:

```sh
swift run -c release voxthumb model.vox model.png 1024
swift run -c release voxthumb --bench 256 *.vox   # CPU time, triangles, peak memory
```

## Using the library

The package exposes `VoxKit` (parser, scene graph, mesher; Foundation only) and `VoxRender` (SceneKit scene, offscreen renderer, preview view):

```swift
.package(url: "https://github.com/Springfolk/voxlook.git", from: "1.0.0")
```

```swift
let file = try VoxFile(contentsOf: url)
let mesh = file.models[0].mesh(palette: file.palette, surfaces: file.surfaces)   // positions, normals, colours (AO baked), indices, parts
let image = try VoxThumbnailRenderer.render(contentsOf: url, pixelSize: CGSize(width: 512, height: 512))
```

## Not yet

- Materials are approximated: no refraction, light from emissive voxels, roughness, or clouds (`_media` draws as glass).

## Contributing

Issues and pull requests are welcome. `make test` runs the suite. The test fixtures are built in code, so no third-party models live in the repo. See [docs/](docs/) for how it works.

## Licence

[MIT](LICENSE). MagicaVoxel is made by [ephtracy](https://ephtracy.github.io); VoxLook isn't affiliated with it.
