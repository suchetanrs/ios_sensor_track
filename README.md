# VaultSync

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
   **VaultSync-ipa** artifact and unzip to `VaultSync.ipa`.
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
