# Changelog

All notable changes are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-11-21

### Added

- Automatic updates with Sparkle 2.10.1: a daily check, **Thanos › Check for Updates…**, and a Settings window to turn automatic checks and installs on or off. Updates are verified with an EdDSA signature. This is the first version that can update itself; earlier versions need one manual download.

### Changed

- Thanos now makes one network request: the update check against this repository's releases. See PRIVACY.md.

## [0.2.0] — 2026-11-21

### Changed

- The bundle identifier is now `com.danyilproskurka.thanos`, registered to the developer team. macOS treats this as a new app, so grant Full Disk Access to Thanos again after updating, and remove the old entry from the list.

## [0.1.1] — 2026-11-21

### Fixed

- Duplicates no longer offers files inside git repositories or worktrees. Identical tracked files across worktrees (test fixtures, data files) are part of the repositories, not junk, and are often APFS clones that free little space.

## [0.1.0] — 2026-11-21

First development preview.

- Parallel disk scanner that stays on one filesystem and skips other apps' containers without Full Disk Access.
- Overview with storage bar, category donut, biggest folders and smart suggestions.
- Explorer with interactive sunburst and treemap.
- Detection of app leftovers, caches and logs, developer junk, installers, duplicates, large forgotten files and the Trash.
- Removal through the Trash with confirmation; overlapping findings are never counted twice.

[0.3.0]: https://github.com/danielproj/thanos/releases/tag/v0.3.0
[0.2.0]: https://github.com/danielproj/thanos/releases/tag/v0.2.0
[0.1.1]: https://github.com/danielproj/thanos/releases/tag/v0.1.1
[0.1.0]: https://github.com/danielproj/thanos/releases/tag/v0.1.0
