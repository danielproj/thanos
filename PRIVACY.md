# Privacy

Thanos runs entirely on your Mac.

- **One network request: update checks.** Once a day (and when you choose Thanos › Check for Updates…), Thanos downloads the update feed from GitHub (`github.com/danielproj/thanos/releases`). It sends no system profile, analytics or identifiers beyond what any web request carries (your IP address and the app version in the user agent). You can turn automatic checks off in Thanos › Settings. Updates are verified with an EdDSA signature and Apple notarization before they are installed.
- **Nothing else.** No analytics, telemetry or crash reporting.
- **Read-only by default.** Scanning reads file and folder metadata (names, sizes, dates). File contents are read only to compare possible duplicates, using SHA-256, on your Mac.
- **Nothing is stored.** Scan results live in memory and are gone when you quit.
- **Removal is always your choice.** Files are moved to the Trash only after you confirm. Emptying the Trash, which is permanent, asks separately.
- **Installed apps.** To recognise leftovers, Thanos asks Spotlight and LaunchServices which apps are installed.
