# Privacy

Thanos runs entirely on your Mac.

- **No network.** Thanos makes no network connections: no analytics, telemetry, crash reporting or update checks.
- **Read-only by default.** Scanning reads file and folder metadata (names, sizes, dates). File contents are read only to compare possible duplicates, using SHA-256, on your Mac.
- **Nothing is stored.** Scan results live in memory and are gone when you quit.
- **Removal is always your choice.** Files are moved to the Trash only after you confirm. Emptying the Trash, which is permanent, asks separately.
- **Installed apps.** To recognise leftovers, Thanos asks Spotlight and LaunchServices which apps are installed.
