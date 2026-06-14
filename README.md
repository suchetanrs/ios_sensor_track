# SensorTrack

A minimal SwiftUI iOS app that displays live readings from the three motion sensors
as three lines on screen:

- Accelerometer (x, y, z)
- Gyroscope (x, y, z)
- Magnetometer (x, y, z)

There is **no Mac required**. GitHub Actions compiles it for you in the cloud and
produces an **unsigned `.ipa`** that you sideload onto your iPhone for free.

## How to get the app onto your phone

### 1. Push this to a **public** GitHub repo
Upload the *contents* of this folder so that `project.yml` and `.github/` sit at the
repo root.

### 2. Let GitHub build it
On every push, the workflow in `.github/workflows/build.yml` runs on a free macOS
runner and builds the app. (You can also trigger it manually: **Actions → Build iOS →
Run workflow**.)

### 3. Download the `.ipa`
Open the finished run under the **Actions** tab → **Artifacts** → download
`SensorTrack-ipa`. Unzip it to get `SensorTrack.ipa`.

### 4. Sideload it (free, no paid Apple account)
The `.ipa` is **unsigned** — your sideloading tool signs it with your free Apple ID:

- **AltStore** (Windows/Mac): install AltServer, then add `SensorTrack.ipa`. It
  auto-refreshes the 7-day signature in the background.
- **Sideloadly** (Windows/Mac): drag in the `.ipa`, enter your Apple ID, click Start.

A free Apple ID lets you run it; the signature expires after **7 days** (AltStore
re-signs automatically). A paid Apple Developer account ($99/yr) would extend that to
a year, but it is **not** required.

## Notes
- Sensors only produce real data on a physical device, not the Simulator.
- The first build takes a few minutes (it installs XcodeGen and compiles).
