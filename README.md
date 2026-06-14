# SensorTrack

A personal iOS app that keeps an Obsidian vault in sync with a GitHub repo. It
periodically **pulls** remote changes, **warns via a notification on merge
conflicts**, then **pushes** your local changes — about every 30 seconds, with a
best-effort background mode. Everything is stored on the device.

> Built to be compiled in the cloud (GitHub Actions) and sideloaded — no Mac needed.

## What it does

- Stores your **GitHub username + personal access token** once (token in the iOS
  Keychain). Editable anytime in **Settings**.
- You pick the **vault folder** on the device and enter the **repo** (`owner/repo`
  or a full URL) and **branch**.
- Every 30 seconds it: pull → if a file changed on *both* sides, save the remote
  version as a `… (conflict <time>)` copy and **send a notification** → push all
  local changes (and conflict copies).
- Keeps an on-screen **log** of every operation.

### How syncing works (important)

This uses **GitHub's HTTPS API**, not real `git`, so it's a **file-level** sync,
not a line-level merge:

- It compares each file's git blob hash between local, remote, and the last synced
  state to decide add / modify / delete on each side.
- A **conflict** = the same file changed locally *and* remotely since the last sync.
  Your local copy is kept, the remote copy is saved beside it, and you get a
  notification. Nothing is silently overwritten.
- Hidden folders (`.git`, `.obsidian`, `.trash`, `.DS_Store`) are **not** synced.

## Background behavior — read this

iOS does **not** allow a guaranteed 30s background timer. This app uses a
low-power **location keep-alive** to stay running, so:

- **Foreground:** reliable ~30s syncs.
- **Background:** ~30s while the keep-alive holds the app alive — but iOS can still
  suspend it. Expect occasional gaps.
- For best results: grant **Always** location permission, enable **Background App
  Refresh** for the app, and keep the phone **charging** (the keep-alive uses
  battery).

## Build & install (no Mac)

1. Push the **contents** of this folder to a **public** GitHub repo so `project.yml`
   and `.github/` are at the repo root.
2. GitHub Actions builds it (Actions → *Build iOS* → run/auto). Download the
   **SensorTrack-ipa** artifact and unzip to `SensorTrack.ipa`.
3. Sideload with AltServer-Linux (free Apple ID).
4. On the phone: enable **Developer Mode** (Settings → Privacy & Security), then
   **Trust** your Apple ID cert under VPN & Device Management.

## First run

1. **Settings** → enter username, token, repo, branch; **Choose vault folder**;
   **Save settings**.
2. **Sync** tab → **Start syncing**. Grant **notifications** and **Always**
   location when prompted.

## Notes / limits

- The token needs **repo contents read/write** scope (a classic PAT with `repo`,
  or a fine-grained PAT with Contents: Read and write).
- Very large vaults are re-hashed each cycle; fine for typical note vaults.
- A free-signed build's signature expires after 7 days — re-run AltServer to refresh.

---

# Sleep Tracker

The app's second feature (home screen → **Sleep Tracker**) is a phone-on-mattress
sleep tracker. Put the phone on the mattress near your pillow, plugged in, and tap
**Start tracking**. All sleep code lives in `Sources/Sleep/` and is independent of the
Obsidian sync.

## How it works

- **Actigraphy (movement).** The accelerometer (Core Motion `userAcceleration`, gravity
  removed) is sampled at ~10 Hz and bucketed into **60-second epochs** — only the
  per-epoch activity *count* is kept, never raw samples. Each epoch is scored
  asleep/awake with the **Cole-Kripke** algorithm, then cleaned up with **Webster
  rescoring** rules.
- **Sound (optional).** With the mic toggle on, Apple's built-in **SoundAnalysis**
  classifier flags **snoring/breathing** on-device (nothing is recorded or uploaded).
  The active audio session also keeps the app alive overnight with the screen locked.
- **Background.** Mic off → keep the app open (the screen stays on). Mic on → the screen
  can lock; the `audio` background mode keeps tracking alive. **Force-quitting** the app
  (swiping it away in the app switcher) stops tracking — iOS does not relaunch a
  force-quit app, so don't swipe it away overnight.
- **Crash/kill recovery.** The in-progress night is checkpointed to disk every epoch
  (`active-session.json`). If the app is terminated, the next launch recovers the
  session and resumes it; the time the app was dead is filled as still/asleep epochs.
- **Output.** Each night is saved on-device (`Documents/SleepSessions/`) with a
  **hypnogram** (Swift Charts), sleep efficiency, onset latency, WASO, awakenings, and
  snore minutes. Sessions are also written to **Apple Health** (`sleepAnalysis`).

## Limits / notes

- Phone-only actigraphy distinguishes **sleep vs. wake**, not sleep *stages*
  (REM/deep), so Health gets `inBed` / `asleepUnspecified` / `awake` only.
- The Cole-Kripke weights were tuned for research wrist counts; the scale/threshold in
  `ColeKripkeClassifier` are exposed for calibration against real phone data.
- **HealthKit** needs the HealthKit entitlement, which a *free* sideload profile can't
  grant — the writer fails gracefully without it; enabling it for real needs a paid
  Apple Developer account + the HealthKit capability on the target.
- Pure engine logic (aggregator, Cole-Kripke, rescoring, metrics) is unit-tested in
  `Tests/` — run with `xcodebuild test` on a Mac/simulator (the cloud build only
  archives the app).
