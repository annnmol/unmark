# Getting started

## Install the external tools

Install FFmpeg, including FFprobe, using your preferred method from the [FFmpeg download page](https://ffmpeg.org/download.html). If you already use [Homebrew](https://brew.sh/), run:

```sh
brew install ffmpeg
```

Check your installation:

```sh
ffmpeg -version
ffprobe -version
ffmpeg -hide_banner -filters
```

The filters list must contain `delogo`. No Node.js or npm dependencies are needed.

## Build and run

1. Download or clone this repository.
2. Open `Unmark.xcodeproj` in Xcode 26.2 or newer.
3. Select the Unmark scheme and My Mac destination.
4. Select your own signing team if Xcode requests one. No maintainer signing credentials are included.
5. Press Command-R.

To build an unsigned Release app from the repository root:

```sh
xcodebuild -project Unmark.xcodeproj -scheme Unmark \
  -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
```

The app is generated at `build/Build/Products/Release/Unmark.app`. This command does not create a signed/notarized public release.

## First use

1. Open Tools at the bottom of the sidebar and click Test tools.
2. If necessary, choose the folder containing both executables. Common Homebrew locations are detected automatically.
3. Add images by dragging them onto the window or clicking Add images.
4. Choose Small, Large, or Custom. For Custom, drag a rectangle with a little space around the mark and the image edges.
5. Click Clean image. Repeat with another area to stack edits.
6. Click blank canvas to hide the rectangle for inspection. Click the image, draw again, or change modes to show it.
7. Choose Export image/Export PNG or Export all, then select the destination. A confirmation appears after saving finishes.

Each input must be 10 MB or smaller and no larger than 25 megapixels. Input images are not modified. Still images only; video is not supported.

## Settings and tool memory

Open Settings from the sidebar or with Command-comma. Choose PNG (the default) or Same as input. Unsupported export encoders use PNG and show an explanation after saving.

Tool paths and the last check result survive restarts. They are rechecked automatically when cleanup starts; changing the selected tool folder clears the old result.

## Cancel, reset, or clear data

- Cancel stops cleanup and skips remaining images; already completed edits stay available.
- Export cancellation stops between encoding/writing steps. The notice reports how many files were saved.
- Reset discards edits on the selected image.
- Tools → Clear temporary data discards all unexported edits in this window after confirmation.
- Closing a window clears its temporary results. Export images you want to keep before closing.

## Before publishing a release

- Verify pick/drop, zoom/pan, custom selection, consecutive cleanups, Reset, and batch export in the actual app.
- Check tool discovery on a fresh user account, missing tools, cancellation, and timeout/error recovery.
- Verify completed-export feedback, both format preferences, and clearing temporary data.
- Check image quality on your intended image types, including transparency and rotated photos.
- Sign/notarize the distributable with your own Apple credentials and verify it on another Mac.
- Add screenshots, version-specific release notes, and a downloadable release artifact.

The source repository contains no automated test cases by maintainer preference. The GitHub workflow performs a build only.

## GitHub release workflow

The copied release workflow has been adapted for this root-level Unmark Xcode project. It does not use a `macos/` subfolder, a separate release script, Cogi names, or `create-dmg`.

The build and release workflows use the macOS 26 runner with Xcode 26.2. The release workflow builds a universal app (Apple Silicon and Intel), adds ad-hoc signatures, packages a DMG and ZIP, generates checksums, and publishes the release. It performs no tests.

After committing and pushing the source, create and push a version tag:

```sh
git tag -a v0.1.0 -m "Unmark 0.1.0"
git push origin v0.1.0
```

Use a new `vMAJOR.MINOR.PATCH` tag for each release. The tag controls the app version and asset filenames. The workflow uses GitHub's automatically provided token, with `contents: write`; no custom PAT is required. Enable Actions and ensure repository or organization rules allow the workflow to create releases.

These downloadable builds are not Developer ID signed or notarized. For a public release with normal macOS trust, add your own Developer ID certificate and Apple notarization credentials in a separate signing workflow update. Never commit certificates or passwords. The first hosted universal build and downloaded DMG should be checked on both architectures before announcing support; local verification in the development environment covered Apple Silicon only.
