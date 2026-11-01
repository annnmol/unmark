# Unmark

A local macOS image-cleanup app built with SwiftUI. Remove small marks with two sparkle presets, or draw a custom rectangle. Images are processed on your Mac using your installed FFmpeg; no account, server, Node.js, or image upload is required.

## Features

- Pick or drag multiple images into a workspace.
- Small and large sparkle presets, plus a custom cleanup rectangle.
- Consecutive cleanups build on the previous result.
- Zoom with +/−, Fit, Command-scroll, or a trackpad pinch; scroll to pan.
- Click blank canvas to hide the selection; click the image to show it again.
- Compare with the original, or Reset to discard edits.
- Export one image or a batch, with completed-save feedback and Show in Finder.
- PNG by default; optionally preserve the input format when macOS can encode it.
- Saved tool checks, cancellable operations, and automatic temporary-file cleanup.

## Requirements

- macOS 15.8 or newer (the current deployment target).
- Xcode 26.2 or newer with the Swift 6.2 compiler to build from source.
- User-installed `ffmpeg` and `ffprobe`; FFmpeg must include the `delogo` filter.

Unmark does not install tools automatically or bundle FFmpeg. See [Getting started](docs/GETTING_STARTED.md) for installation, build, and usage instructions.

## Image limits and formats

Each input image may be at most **10 MB (10,000,000 bytes)** and **25 megapixels**. The pixel limit protects memory usage for highly compressed images. There is no fixed image-count or combined-file-size limit. Large batches can still consume significant memory and disk space; use smaller batches on constrained Macs.

Input formats: PNG, JPG/JPEG, TIFF, BMP, HEIC, and WebP. Only the first frame/page is processed; animations and multi-page documents are not preserved. Videos are not supported.

Exports default to PNG. “Same as input” uses native macOS encoders; unavailable formats fall back to PNG with an explanation in the completed-export notice. WebP export is unavailable on some Macs. JPEG and HEIC are re-encoded at high quality and can introduce compression loss.

## How cleanup works

FFmpeg's `delogo` estimates a replacement from surrounding pixels. It works best on small marks over simple backgrounds; it cannot recover artwork hidden under a logo. Large areas, faces, and detailed textures can leave visible patches.

The app normalizes images to an **8-bit sRGB working image**. Only the selected rectangle from FFmpeg's processed result is copied back into that working image, preserving the surrounding working pixels. Original metadata, HDR, wide-gamut profiles, and higher bit depths are not preserved. This is not an archival photo editor.

Tool checks have a 10-second limit per command; each FFmpeg cleanup command has a 60-second limit. Cancel stops the current command and skips the rest of the batch. Previously completed edits stay available. Export cancellation takes effect between encoding/writing steps; an individual native encoding step is not interrupted halfway through.

## Temporary data and privacy

Original files are read, not edited. Export creates separate files; the app prevents selecting an imported original as an export destination.

Cleanup results live in app-owned temporary workspace folders. Closing a window clears its results and cancels its work. Tools → Clear temporary data also discards unexported edits in that window; original and exported files are kept. Abandoned workspace folders from exited processes are removed on the next launch. Workspaces are not restored after quitting.

Export preferences, tool paths, and the last check result are stored locally in macOS UserDefaults. Unmark contains no analytics, telemetry, or network image processing. Opening the installation link in Tools uses your browser.

## Code structure

- `ContentView.swift`, `ZoomCanvas.swift`: editor UI and native scrolling/zooming.
- `Workspace.swift`: window state and operation coordination.
- `CleanupEngine.swift`: cleanup worker and tool discovery.
- `ProcessRunner.swift`: external process deadlines and cancellation.
- `ImageFormats.swift`: validation, normalization, compositing, and encoding.
- `ExportService.swift`: background image export.
- `TemporaryStorage.swift`, `WindowLifecycle.swift`: workspace lifetime and cleanup.
- `AppSettingsView.swift`: persistent export preference.

The GitHub workflow builds the Release configuration without signing. No test cases or test target are included in this repository.

## First release scope

This version is intended for direct macOS distribution with user-installed FFmpeg. App Sandbox is disabled for that integration. It is not currently configured for the Mac App Store. The local repository build is unsigned. The release workflow adds ad-hoc signatures, which do not provide Developer ID trust or notarization; macOS may block downloaded apps. Developer ID signing/notarization requires your own Apple credentials and release validation.

Push a version tag such as `v0.1.0` to trigger `.github/workflows/release.yml`. It builds Apple Silicon and Intel, creates `Unmark-v0.1.0-universal.dmg` and `.zip` plus SHA-256 checksums, then publishes a GitHub release using the repository-provided token. No personal token or signing secrets are required for this ad-hoc-signed release path. Actions must be enabled and repository policy must permit release creation. See [release instructions](docs/GETTING_STARTED.md#github-release-workflow).

MCP integration is planned for a later release and is not included here.

## Contributing

Open an issue with your macOS/Xcode version, tool versions, image format/dimensions, and reproduction steps. Avoid attaching private images; a non-sensitive sample is preferable. Keep changes focused and verify both individual and batch workflows manually.

## License

[MIT](LICENSE), copyright 2026 Anmol Tanwar. FFmpeg is a separate external dependency, distributed under its own applicable licenses; it is not covered by Unmark's MIT license.
