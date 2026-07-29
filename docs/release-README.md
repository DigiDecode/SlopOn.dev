# SlopOn

SlopOn bundles two things: the **slopon_dev** desktop app (the frontend) and
the **slopon-backend** server, a self-hosted Node.js backend that the app
connects to over WebSocket. This zip contains both, ready to run on your
machine.

## Contents

```
slopon-latest-<platform>/
  README.md        ← this file
  frontend/        ← the slopon_dev desktop app for your platform
  backend/         ← the self-hosted backend server (Node.js)
```

- **Windows** (`slopon-latest-windows-x64.zip`): `frontend/` contains
  `slopon_dev.exe` plus its DLLs and a `data/` folder.
- **Linux** (`slopon-latest-linux-x64.zip`): `frontend/` contains the
  `slopon_dev` executable, `lib/` (shared libraries) and `data/`.
- **macOS** (`slopon-latest-macos-x64.zip` / `slopon-latest-macos-arm64.zip`):
  `frontend/` contains the `slopon_dev.app` bundle. Pick the **arm64** zip on
  Apple Silicon Macs and the **x64** zip on Intel Macs.

`backend/` is identical on every platform: `index.js` (the server bundle),
`package.json`, `migrations/`, `prompts/` and its own `README.md`.

## Prerequisites

- **Node.js ≥ 20** — Node 20 and 22 are supported and verified. Later majors
  (e.g. 24) are not yet verified.
- **git** on your `PATH` — the server shells out to git at runtime.
- **pnpm** or **npm** for the one-time dependency install.
- Network access for that one-time install.

## 1. Run the backend

```sh
cd backend
pnpm install
node index.js
```

(or `npm install`, and/or `pnpm start` / `npm start` instead of
`node index.js`)

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

- **Windows:** double-click `frontend\slopon_dev.exe` (or run it from a
  terminal).
- **Linux:** `./frontend/slopon_dev` — if the binary lost its executable
  bit during extraction, run `chmod +x frontend/slopon_dev` first.
- **macOS:** `open frontend/slopon_dev.app` (or double-click it in Finder).
  macOS builds require Big Sur 11.0 or newer.

Enter the backend's API key when the app asks for it.

## Unsigned-build warnings

These builds are **unsigned**, so expect a warning on first launch:

- **macOS (Gatekeeper):** right-click (control-click) `slopon_dev.app` and
  choose **Open**, then confirm.
- **Windows (SmartScreen):** click **More info**, then **Run anyway**.
