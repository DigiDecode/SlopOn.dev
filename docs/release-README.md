# SlopOn

SlopOn bundles two things: the **slopon_dev** desktop app (the frontend) and
the **slopon-backend** server, a self-hosted Node.js backend that the app
connects to over WebSocket. This archive contains both, ready to run on your
machine.

## Contents

```
slopon-<platform>/
  README.md        ← this file
  frontend/        ← the slopon_dev desktop app for your platform
  backend/         ← the self-hosted backend server (Node.js)
  launcher/        ← one-command launcher (backend-then-app) + --stop helper
```

- **Windows** (`slopon-windows-x64.zip`): `frontend/` contains
  `slopon_dev.exe` plus its DLLs and a `data/` folder.
- **Linux** (`slopon-linux-x64.tar.gz`): `frontend/` contains the
  `slopon_dev` executable, `lib/` (shared libraries) and `data/`.
- **macOS** (`slopon-macos-x64.zip` / `slopon-macos-arm64.zip`):
  `frontend/` contains the `slopon_dev.app` bundle. Pick the **arm64** zip on
  Apple Silicon Macs and the **x64** zip on Intel Macs.

`backend/` is identical on every platform: `index.js` (the server bundle),
`package.json`, `package-lock.json`, `migrations/`, `prompts/` and its own
`README.md`. `launcher/` ships `launcher.mjs` plus `slopon.sh` (macOS/Linux)
and `slopon.cmd` (Windows).

## Prerequisites

- **Node.js ≥ 20** — Node 20 and 22 are supported and verified. Later majors
  (e.g. 24) are not yet verified. The one-liner installer below provisions a
  pinned Node 22 runtime automatically when your system Node is missing or
  an unverified major.
- **git** on your `PATH` — the server shells out to git at runtime (the
  installer warns but continues without it).
- **pnpm** or **npm** for the one-time dependency install.
- Network access for that one-time install.

## Quick install (machines not yet installed)

If you extracted this archive by hand you did not need to — the one-liner
does everything (download, SHA-256 verification, Node runtime, dependencies,
launcher shortcut):

- **macOS** (Apple Silicon and Intel) and **Debian Linux** x64:

  ```sh
  curl -fsSL https://slopon.dev/install.sh | sh
  ```

- **Windows** x64 (Windows PowerShell):

  ```powershell
  powershell -NoProfile -c "irm https://slopon.dev/install.ps1 | iex"
  ```

Installs per-user (no admin). Windows on ARM and Linux ARM are not supported
yet — the installer refuses with a clear message. Upgrading = re-run the
one-liner with SlopOn stopped (backend **and** app); `~/.slopon` (config,
database, attachments) is preserved untouched.

## 1. Run the backend (and the app)

The recommended start is the launcher — it starts the backend only if it is
not already running, waits until it is ready to accept connections, and then
launches the app (the app reads the same `~/.slopon/config.json` and connects
automatically — no key typing on a fresh install):

```sh
# macOS / Linux
./launcher/slopon.sh           # start (backend first, then the app)
./launcher/slopon.sh --stop    # stop the backend

# Windows
launcher\slopon.cmd            # start
launcher\slopon.cmd --stop     # stop (best-effort hard kill)
```

Re-running the launcher while the backend is up never spawns a second
backend. Logs: `~/.slopon/logs/backend.log` (server output) and
`~/.slopon/logs/launcher.log` (launcher diagnostics). If the backend cannot
become ready within 60 s, the launcher logs the failure, shows a best-effort
dialog, and exits non-zero.

### Manual path (classic)

Dependencies (the shipped `package-lock.json` pins the tested tree — `npm ci`
reproduces it; `npm install` / `pnpm install` also work):

```sh
cd backend
npm ci
node index.js
```

(or `pnpm install` instead of `npm ci`, and/or `pnpm start` / `npm start`
instead of `node index.js`)

pnpm 11 prints a warning that it ignores the `pnpm` field in `package.json` —
this is expected and harmless: pnpm 11 approves the `better-sqlite3` native
build via the shipped `pnpm-workspace.yaml` (`allowBuilds`), while pnpm 10.x
uses the `package.json` field. Do **not** run `pnpm approve-builds`; the
approval is already shipped.

On first run the server provisions its configuration under `~/.slopon`
(`config.json`, SQLite database, attachments) and prints a freshly generated
**API key** in a banner. **Keep this key** — the frontend needs it to connect,
and it is required for every WebSocket connection.

After startup the server logs its version and listens for WebSocket
connections on the port written to `~/.slopon/config.json`. See
`backend/README.md` for details.

## 2. Run the frontend

If you started via the launcher (or the one-liner installer's shortcut), the
app is already running and connected — the launcher only launches it after
the backend is ready, and both read the same `~/.slopon/config.json`.

Starting it by hand:

- **Windows:** double-click `frontend\slopon_dev.exe` (or run it from a
  terminal).
- **Linux:** `./frontend/slopon_dev` — if the binary lost its executable
  bit during extraction, run `chmod +x frontend/slopon_dev` first.
- **macOS:** `open frontend/slopon_dev.app` (or double-click it in Finder).
  macOS builds require Big Sur 11.0 or newer.

Enter the backend's API key when the app asks for it (it lives in
`~/.slopon/config.json` under `server.apiKey` — the launcher flow enters it
for you).

## Unsigned-build warnings

These builds are **unsigned**, so expect a warning on first launch:

- **macOS (Gatekeeper):** right-click (control-click) `slopon_dev.app` and
  choose **Open**, then confirm.
- **Windows (SmartScreen):** click **More info**, then **Run anyway**.
