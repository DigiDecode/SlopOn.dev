#!/bin/sh
# SlopOn installer for macOS (x64, Apple Silicon) and Debian-family Linux (x64).
#
#   curl -fsSL https://slopon.dev/install.sh | sh
#
# Pure POSIX sh (dash-compatible): no here-strings, no [[ ]], no arrays, no
# /dev/tcp. Downloads the latest release archive, verifies its SHA-256 against
# the GitHub release API asset digest, provisions a pinned Node 22 runtime
# under the install root when the system Node is missing or an unverified
# major, runs `npm ci` in backend/, installs a platform launcher shortcut,
# and puts a `slopon` command on PATH (~/.local/bin).
# ~/.slopon (config, database, attachments) is never touched.
#
# Environment overrides (CI / power users):
#   SLOPON_ARCHIVE=path|url   install from a local file (checksum SKIPPED for
#                             local paths) or an explicit URL (checksum verified)
#   SLOPON_GH_TOKEN=tok       GitHub API token (avoids anonymous rate limits)
#   SLOPON_SKIP_CHECKSUM=1    skip release-archive digest verification (CI only)
set -u

REPO="DigiDecode/SlopOn.dev"
GH_API_URL="https://api.github.com/repos/$REPO/releases/latest"
RELEASES_URL="https://github.com/$REPO/releases"
DEFAULT_DL_BASE="https://github.com/$REPO/releases/latest/download"
# Pinned on-demand runtime for machines without a verified Node 20/22.
# Update procedure: take the newest 22.x from https://nodejs.org/dist/index.json
# and mirror the change in install/install.ps1 (the pins must match).
NODE_VERSION="22.23.2"
NODE_DIST_BASE="https://nodejs.org/dist"

fail() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "warning: $*" >&2
}

: "${HOME:?HOME is not set — cannot determine per-user install locations}"
umask 022

# ── 1. Gate: OS + architecture ─────────────────────────────────────────────
os=$(uname -s)
arch=$(uname -m)
case "$os" in
  Darwin)
    # uname -m reports i386/x86_64 under Rosetta — trust the CPU instead.
    if sysctl -n hw.optional.arm64 >/dev/null 2>&1 && [ "$(sysctl -n hw.optional.arm64)" = "1" ]; then
      arch="arm64"
    fi
    case "$arch" in
      arm64) platform="macos-arm64"; asset="slopon-macos-arm64.zip"; ext="zip"
             node_os_arch="darwin-arm64" ;;
      x86_64) platform="macos-x64"; asset="slopon-macos-x64.zip"; ext="zip"
              node_os_arch="darwin-x64" ;;
      *) fail "unsupported macOS architecture '$arch'. See $RELEASES_URL for supported builds." ;;
    esac
    ;;
  Linux)
    case "$arch" in
      x86_64) platform="linux-x64"; asset="slopon-linux-x64.tar.gz"; ext="tar.gz"
              node_os_arch="linux-x64" ;;
      *) fail "unsupported Linux architecture '$arch' (only x64 is supported; ARM builds are not available). See $RELEASES_URL." ;;
    esac
    # Debian-family glibc is the supported line — musl (Alpine) is not.
    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
      fail "musl libc detected (Alpine?) — not supported. Use a Debian/Ubuntu glibc system."
    fi
    ;;
  *) fail "unsupported operating system '$os'. See $RELEASES_URL." ;;
esac

case "$platform" in
  macos-*) install_root="$HOME/Applications/SlopOn" ;;
  linux-*) install_root="$HOME/.local/opt/slopon" ;;
esac
SLOPON_HOME="$HOME/.slopon"
CONFIG_FILE="$SLOPON_HOME/config.json"
PID_FILE="$SLOPON_HOME/backend.pid"
stop_command="$install_root/launcher/slopon.sh --stop"

echo "==> SlopOn installer: $platform -> $install_root"

# ── 2. Archive source + SHA-256 verification ───────────────────────────────
stage_base=$(dirname "$install_root")
mkdir -p "$stage_base" "$SLOPON_HOME" || fail "cannot create install directories under \$HOME"
tmp=$(mktemp -d "$stage_base/.slopon-stage.XXXXXX") || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT INT TERM

archive_src="${SLOPON_ARCHIVE:-$DEFAULT_DL_BASE/$asset}"
case "$archive_src" in
  http://*|https://*) verify_digest=yes; need_download=yes ;;
  *)                 verify_digest=no;  need_download=no ;;  # local file path (CI seam)
esac

if [ "$need_download" = yes ]; then
  echo "==> downloading $asset"
  curl -fSL --retry 3 -o "$tmp/$asset" "$archive_src" || fail "download failed: $archive_src"
  archive="$tmp/$asset"
else
  archive="$archive_src"
  [ -f "$archive" ] || fail "SLOPON_ARCHIVE file not found: $archive"
  echo "==> using local archive $archive (digest verification skipped by design for local files)"
fi

if [ "${SLOPON_SKIP_CHECKSUM:-0}" = "1" ]; then
  warn "SLOPON_SKIP_CHECKSUM=1 — skipping archive digest verification (CI-only escape hatch)"
  verify_digest=no
fi

compute_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "neither sha256sum nor shasum is available — cannot verify the download"
  fi
}

if [ "$verify_digest" = yes ]; then
  echo "==> verifying SHA-256 against the GitHub release API"
  api_json="$tmp/release-api.json"
  if [ -n "${SLOPON_GH_TOKEN:-}" ]; then
    api_code=$(curl -sS -o "$api_json" -w '%{http_code}' \
      -H "Authorization: Bearer $SLOPON_GH_TOKEN" -H "Accept: application/vnd.github+json" \
      "$GH_API_URL")
  else
    api_code=$(curl -sS -o "$api_json" -w '%{http_code}' \
      -H "Accept: application/vnd.github+json" "$GH_API_URL")
  fi
  case "$api_code" in
    200) ;;
    403|429)
      fail "GitHub API rate limit reached (HTTP $api_code) — retry in a while, or set SLOPON_GH_TOKEN to a token and re-run."
      ;;
    *) fail "GitHub release API returned HTTP $api_code — cannot verify the archive digest." ;;
  esac
  expected=$(awk -v a="$asset" '
    /"name":/ { inasset = (index($0, "\"" a "\"") > 0) }
    inasset && /"digest":/ { sub(/.*"digest": *"/, ""); sub(/".*/, ""); print; exit }
  ' "$api_json")
  [ -n "$expected" ] || fail "the GitHub release API exposed no digest for '$asset' — refusing to install unverified (API contract change?)"
  expected=${expected#sha256:}
  actual=$(compute_sha256 "$archive")
  if [ "$actual" != "$expected" ]; then
    fail "SHA-256 mismatch for $asset (expected $expected, got $actual) — the download was corrupted or tampered with; not installing."
  fi
  echo "    digest OK ($actual)"
fi

# ── 3. Refuse to upgrade while SlopOn is running ───────────────────────────
if [ -f "$PID_FILE" ]; then
  running_pid=$(sed -n 's/^\([0-9][0-9]*\).*/\1/p' "$PID_FILE" | head -n 1)
  if [ -n "${running_pid:-}" ] && kill -0 "$running_pid" 2>/dev/null; then
    fail "the SlopOn backend (PID $running_pid) is running.
         Stop it first:  $stop_command
         then re-run the installer."
  fi
fi
if [ -f "$CONFIG_FILE" ]; then
  cfg_port=$(sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$CONFIG_FILE" | head -n 1)
  cfg_ip=$(sed -n 's/.*"listenIp"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1)
  [ -n "$cfg_ip" ] || cfg_ip="127.0.0.1"
  [ "$cfg_ip" = "0.0.0.0" ] || [ "$cfg_ip" = "::" ] && cfg_ip="127.0.0.1"
  if [ -n "${cfg_port:-}" ] && command -v node >/dev/null 2>&1; then
    # Pure POSIX sh has no /dev/tcp (that is a bashism); node — which must
    # exist for a manually-started backend anyway — provides the TCP probe.
    if node -e '
      const net = require("net");
      const s = net.connect({ host: process.argv[1], port: Number(process.argv[2]) });
      s.setTimeout(1500, () => { s.destroy(); process.exit(1); });
      s.on("connect", () => process.exit(0));
      s.on("error", () => process.exit(1));
    ' "$cfg_ip" "$cfg_port" 2>/dev/null; then
      fail "something is listening on $cfg_ip:$cfg_port (the backend was likely started manually).
         Stop it first:  $stop_command
         then re-run the installer."
    fi
  fi
fi
if command -v pgrep >/dev/null 2>&1 && pgrep -f slopon_dev >/dev/null 2>&1; then
  fail "the SlopOn app (slopon_dev) is running.
         Close the SlopOn app, then re-run the installer."
fi

# ── 4. Node runtime: system Node 20/22, else a pinned bundled Node 22 ─────
node_kind=""
if command -v node >/dev/null 2>&1; then
  sys_node_version=$(node --version 2>/dev/null || echo "")
  case "$sys_node_version" in
    v20.*|v22.*)
      NODE_BIN=$(command -v node)
      node_kind="system"
      echo "==> using system Node $sys_node_version"
      ;;
    "")
      : # node exists but is broken — fall through to the bundled runtime
      ;;
    *)
      echo "==> system Node $sys_node_version is not a verified major (20/22) — using bundled Node $NODE_VERSION"
      ;;
  esac
else
  echo "==> Node not found on PATH — will provision bundled Node $NODE_VERSION"
fi

if [ "$node_kind" != "system" ]; then
  # Official asset names AND dist directories carry a leading "v"
  # (https://nodejs.org/dist/v22.23.2/node-v22.23.2-linux-x64.tar.gz).
  node_file="node-v$NODE_VERSION-$node_os_arch.tar.gz"
  echo "==> downloading $node_file"
  curl -fSL --retry 3 -o "$tmp/$node_file" "$NODE_DIST_BASE/v$NODE_VERSION/$node_file" \
    || fail "Node runtime download failed"
  curl -fsSL -o "$tmp/SHASUMS256.txt" "$NODE_DIST_BASE/v$NODE_VERSION/SHASUMS256.txt" \
    || fail "could not download SHASUMS256.txt for Node $NODE_VERSION"
  node_expected=$(awk -v f="$node_file" '$2 == f { print $1; exit }' "$tmp/SHASUMS256.txt")
  [ -n "$node_expected" ] || fail "$node_file not listed in SHASUMS256.txt"
  node_actual=$(compute_sha256 "$tmp/$node_file")
  [ "$node_actual" = "$node_expected" ] \
    || fail "Node runtime SHA-256 mismatch (expected $node_expected, got $node_actual)"
  echo "    digest OK ($node_actual)"
  mkdir -p "$install_root/node-runtime"
  # Official tarballs wrap a top-level node-vX-<os>-<arch>/ directory.
  tar -xzf "$tmp/$node_file" -C "$install_root/node-runtime" --strip-components=1 \
    || fail "Node runtime extraction failed"
  NODE_BIN="$install_root/node-runtime/bin/node"
  echo "    bundled runtime installed at $install_root/node-runtime"
fi
NODE_BIN_DIR=$(dirname "$NODE_BIN")
PATH="$NODE_BIN_DIR:$PATH"
export PATH
command -v npm >/dev/null 2>&1 || fail "npm not found next to the resolved Node ($NODE_BIN)"

# ── 5. git (warning only) ──────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
  echo "==> git: $(git --version 2>/dev/null || echo found)"
else
  warn "git is not installed — installation continues, but backend features that shell out to git will fail at runtime. Install git (e.g. 'sudo apt install git' / Xcode Command Line Tools) for full functionality."
fi

# ── 6. Extract + all-or-nothing file replacement ──────────────────────────
echo "==> extracting release payload"
extract_dir="$tmp/extract"
mkdir -p "$extract_dir"
case "$ext" in
  zip)
    # ditto (not unzip) preserves framework symlinks inside the .app.
    ditto -x -k "$archive" "$extract_dir" || fail "archive extraction failed"
    ;;
  tar.gz)
    tar -xzf "$archive" -C "$extract_dir" || fail "archive extraction failed"
    ;;
esac
payload=""
for d in "$extract_dir"/*/; do
  [ -d "$d" ] || continue
  [ -z "$payload" ] || fail "archive wraps more than one top-level directory"
  payload=${d%/}
done
[ -n "$payload" ] || fail "archive does not wrap a top-level slopon-<platform>/ directory"
for need in "$payload/frontend" "$payload/backend" "$payload/launcher"; do
  [ -d "$need" ] || fail "archive payload is missing '$need'"
done

echo "==> installing app files into $install_root"
mkdir -p "$install_root"
# The aside dir lives INSIDE the install root: same filesystem as the payload
# dirs (atomic renames), and it survives the EXIT trap that cleans $tmp — a
# failed restore must never lose the previous version.
aside="$install_root/.slopon-upgrade-aside.$$"
mkdir -p "$aside"
moved_aside=""
for d in frontend backend launcher; do
  if [ -d "$install_root/$d" ]; then
    mv "$install_root/$d" "$aside/$d" || fail "could not move '$d' aside — aborting before any change"
    moved_aside="$moved_aside $d"
  fi
done
restore_aside() {
  for d in $moved_aside; do
    rm -rf "$install_root/$d"
    mv "$aside/$d" "$install_root/$d" || echo "error: could not restore '$d' — previous version is in $aside" >&2
  done
}
if ! { mv "$payload/frontend" "$install_root/frontend" \
    && mv "$payload/backend" "$install_root/backend" \
    && mv "$payload/launcher" "$install_root/launcher"; }; then
  restore_aside
  fail "moving new files into place failed — previous version restored (no partial install)"
fi
if [ -n "$moved_aside" ]; then
  rm -rf "$aside"
fi

# Never trust archived permission bits for things we must execute.
chmod +x "$install_root/launcher/slopon.sh" || fail "could not make launcher/slopon.sh executable"
if [ "$platform" = "linux-x64" ]; then
  chmod +x "$install_root/frontend/slopon_dev" || fail "could not make frontend/slopon_dev executable"
fi
# Record the Node we validated, next to slopon.sh: desktop-menu launches run
# with a minimal PATH (GNOME omits nvm/user dirs), where bare `node` does not
# resolve. slopon.sh prefers node-runtime, then this file, then PATH.
printf '%s\n' "$NODE_BIN" > "$install_root/launcher/node.path" 2>/dev/null \
  || warn "could not record the Node path for the desktop launcher — the menu entry may not start if 'node' is not on the system PATH"

# ── 7. Backend dependencies (lockfile-driven) ──────────────────────────────
echo "==> installing backend dependencies (npm ci)"
(cd "$install_root/backend" && npm ci --no-audit --no-fund) \
  || fail "npm ci failed — see the output above; your install files are in place but the backend has no dependencies yet"

# ── 8. Platform shortcut ───────────────────────────────────────────────────
case "$platform" in
  macos-*)
    app_bundle="$HOME/Applications/SlopOn.app"
    echo "==> creating launcher $app_bundle"
    mkdir -p "$app_bundle/Contents/MacOS"
    cat > "$app_bundle/Contents/MacOS/SlopOn" <<EOF
#!/bin/sh
exec "$install_root/launcher/slopon.sh" "\$@"
EOF
    chmod +x "$app_bundle/Contents/MacOS/SlopOn"
    cat > "$app_bundle/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SlopOn</string>
  <key>CFBundleIdentifier</key><string>dev.slopon.SlopOn</string>
  <key>CFBundleName</key><string>SlopOn</string>
  <key>CFBundleDisplayName</key><string>SlopOn</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
</dict>
</plist>
EOF
    ;;
  linux-*)
    desktop_dir="$HOME/.local/share/applications"
    desktop_file="$desktop_dir/slopon.desktop"
    echo "==> creating launcher $desktop_file"
    mkdir -p "$desktop_dir"
    # Cosmetic-only icon: a failed download must never fail the install —
    # the .desktop is simply written without an Icon= line.
    icon_line=""
    icon_dir="$HOME/.local/share/icons"
    icon_file="$icon_dir/slopon.png"
    if mkdir -p "$icon_dir" 2>/dev/null \
      && curl -fsSL --max-time 20 -o "$icon_file" "https://slopon.dev/brand/favicon-192.png" 2>/dev/null \
      && [ -s "$icon_file" ]; then
      icon_line="Icon=$icon_file"
    else
      warn "could not fetch the menu icon — continuing without it"
      rm -f "$icon_file"
    fi
    {
      echo "[Desktop Entry]"
      echo "Type=Application"
      echo "Name=SlopOn"
      echo "Comment=SlopOn — agentic coding environment"
      echo "Exec=$install_root/launcher/slopon.sh"
      echo "Terminal=false"
      echo "Categories=Development;"
      if [ -n "$icon_line" ]; then
        echo "$icon_line"
      fi
    } > "$desktop_file"
    command -v update-desktop-database >/dev/null 2>&1 \
      && update-desktop-database "$desktop_dir" 2>/dev/null || :
    ;;
esac

# ── 8b. `slopon` command on PATH ──────────────────────────────────────────
bin_dir="$HOME/.local/bin"
echo "==> installing 'slopon' command into $bin_dir"
mkdir -p "$bin_dir" || fail "could not create $bin_dir"
# A generated shim (not a symlink): the install path is baked in, so nothing
# downstream has to resolve symlinks, and every upgrade re-run refreshes it.
cat > "$bin_dir/slopon" <<EOF
#!/bin/sh
# Generated by the SlopOn installer — re-run the installer to refresh.
exec "$install_root/launcher/slopon.sh" "\$@"
EOF
chmod +x "$bin_dir/slopon" || fail "could not make $bin_dir/slopon executable"

# Marked, idempotent PATH block appended to the shell startup files. Which
# files depends on the platform shell: zsh has no first-found fallback chain
# (creating .zprofile/.zshrc suppresses nothing), but bash reads only the FIRST
# of .bash_profile/.bash_login/.profile at login — so pre-existing bash files
# are appended to, never created, to keep that chain intact.
path_block='
# added by the SlopOn installer (puts the slopon command on PATH)
if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
  export PATH
fi'

ensure_path_line() {
  pl_file=$1
  [ -f "$pl_file" ] || touch "$pl_file" 2>/dev/null || { warn "could not create $pl_file"; return 0; }
  grep -q 'SlopOn installer' "$pl_file" 2>/dev/null && return 0
  if printf '%s\n' "$path_block" >> "$pl_file" 2>/dev/null; then
    echo "    PATH line added to $pl_file"
  else
    warn "could not append the PATH line to $pl_file — add $bin_dir to PATH manually"
  fi
}

case "$os" in
  Darwin)
    ensure_path_line "$HOME/.zprofile"
    ensure_path_line "$HOME/.zshrc"
    if [ -f "$HOME/.bash_profile" ]; then ensure_path_line "$HOME/.bash_profile"; fi
    if [ -f "$HOME/.profile" ]; then ensure_path_line "$HOME/.profile"; fi
    ;;
  Linux)
    ensure_path_line "$HOME/.profile"
    if [ -f "$HOME/.bash_profile" ]; then ensure_path_line "$HOME/.bash_profile"; fi
    ;;
esac

# ── 9. Summary ─────────────────────────────────────────────────────────────
echo
echo "SlopOn installed successfully."
echo "  Install root : $install_root"
echo "  Start        : 'slopon' in a NEW terminal, or launch SlopOn from"
echo "                 your applications folder/menu"
echo "                 (direct: $install_root/launcher/slopon.sh)"
# A piped `curl | sh` runs in a child shell — it cannot export PATH back into
# the terminal that launched it, so give the exact line to run right now.
echo "                 (this session: export PATH=\"$HOME/.local/bin:\$PATH\")"
echo "  Stop backend : $stop_command"
echo "  Logs         : $SLOPON_HOME/logs/backend.log and launcher.log"
if [ "$node_kind" != "system" ]; then
  echo "  Node runtime : bundled $NODE_VERSION at $install_root/node-runtime"
fi
echo "  Data (~/.slopon — kept untouched across upgrades): $SLOPON_HOME"
echo "  Upgrade      : re-run this installer with SlopOn stopped."
