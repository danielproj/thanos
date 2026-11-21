# Contributing to Thanos

Thanks for helping! Bug reports, detection ideas and pull requests are all welcome.

## Before you start

- For anything larger than a small fix, open an issue or a discussion first so we can agree on the approach.
- Security problems: please report them privately (see [SECURITY.md](SECURITY.md)), not as a public issue.

## Development

Requires macOS 26+ and Xcode 26+.

```bash
scripts/build-app.sh --open   # build and run
swift test                    # unit tests
scripts/ci.sh                 # everything CI runs
```

`THANOS_SCAN=<path>` starts a scan on launch, which makes UI work much faster than scanning your whole home folder.

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Keep each pull request focused on one change; add or update tests where it makes sense.
3. Make sure `scripts/ci.sh` passes.
4. Fill in the pull request template, with screenshots for UI changes.

Pull requests are squash-merged, so the PR title becomes the commit message — make it a short, imperative summary (`Detect stale Flutter build folders`).

## Adding a detection rule

Detection lives in `Sources/Thanos/Model/CleanupEngine.swift`. A good rule:

- **Is conservative.** If you are not sure an item can be recreated, use *Review*, not *Safe*.
- **Explains itself.** The `reason` text tells the user what the item is and what happens if it goes.
- **Never deletes directly.** Removal always goes through the Trash after a confirmation.

## Code style

Follow the surrounding code: SwiftUI, Swift Concurrency, Liquid Glass (`glassEffect`) for controls and floating surfaces, plain materials for content.

## Releases (maintainers)

Releases are signed and notarized on the maintainer's Mac, so the signing keys never leave it.

1. Add the version to `CHANGELOG.md` and merge it to `main`.
2. Tag and push: `git tag -a vX.Y.Z -m "Thanos X.Y.Z" && git push origin vX.Y.Z`. The `release` workflow checks that the tag is on `main`, matches the changelog, and builds and tests cleanly.
3. Package: `THANOS_NOTARY_PROFILE=<profile> scripts/package-release.sh --version X.Y.Z --build N`. This signs with the Developer ID identity, notarizes and staples the app and disk image, and writes everything to `artifacts/release/`.
4. Publish: `gh release create vX.Y.Z --verify-tag --title "Thanos X.Y.Z — Development Preview" --notes-file artifacts/release/release-notes.md artifacts/release/*`.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
