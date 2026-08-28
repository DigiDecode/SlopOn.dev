#!/usr/bin/env node
// SlopOn launcher — the one-command "backend first, then GUI" start.
//
//   node launcher.mjs          start the backend if needed, wait for TCP
//                               readiness, then launch the desktop app
//   node launcher.mjs --stop   stop the backend and remove the pidfile
//
// The install root is resolved from this file's own location (the launcher
// ships as <install>/launcher/launcher.mjs), so it works from any cwd and
// from platform shortcuts. ~/.slopon is the backend's data dir — the launcher
// only ever touches backend.pid and logs/ inside it, never config or data.
import { spawn, spawnSync } from 'node:child_process';
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const READY_BUDGET_MS = 60_000; // covers fresh-install config provisioning + TCP accept
const STOP_GRACE_MS = 15_000; // SIGTERM/taskkill before the force fallback
const POLL_MS = 500;
const PROBE_TIMEOUT_MS = 1_500;

const IS_WIN = process.platform === 'win32';
const IS_MAC = process.platform === 'darwin';

const installRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const sloponDir = path.join(os.homedir(), '.slopon');
const logsDir = path.join(sloponDir, 'logs');
const configPath = path.join(sloponDir, 'config.json');
const pidfilePath = path.join(sloponDir, 'backend.pid');
const backendLogPath = path.join(logsDir, 'backend.log');
const launcherLogPath = path.join(logsDir, 'launcher.log');

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function log(message) {
  const line = `${new Date().toISOString()} ${message}`;
  try {
    mkdirSync(logsDir, { recursive: true });
    appendFileSync(launcherLogPath, `${line}\n`);
  } catch {
    // Diagnostics logging must never be fatal.
  }
  console.log(line);
}

// Best-effort user-visible dialog on fatal errors. Every platform path is
// wrapped — a dialog failure must never mask the launcher.log write.
function fatalDialog(message) {
  const text = `SlopOn failed to start: ${message} Details: ${launcherLogPath}`;
  try {
    if (IS_WIN) {
      spawn('msg.exe', ['*', '/time:30', text], { windowsHide: true, stdio: 'ignore' });
    } else if (IS_MAC) {
      const escaped = text.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
      spawn('osascript', ['-e', `display alert "SlopOn" message "${escaped}"`], {
        windowsHide: true,
        stdio: 'ignore',
      });
    } else {
      spawn('notify-send', ['SlopOn', text], { windowsHide: true, stdio: 'ignore' });
    }
  } catch {
    // ignore — the log write already happened
  }
}

function probeTcp(host, port, timeoutMs = PROBE_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    const settle = (result) => {
      socket.destroy();
      resolve(result);
    };
    socket.setTimeout(timeoutMs, () => settle(false));
    socket.once('connect', () => settle(true));
    socket.once('error', () => settle(false));
  });
}

// Readiness target from ~/.slopon/config.json. Wildcard listen IPs
// (0.0.0.0 / ::) normalize to 127.0.0.1 — a wildcard bind accepts loopback,
// and a specific bind does not, so normalizing never fabricates reachability.
// Returns null when the config is missing/malformed (fresh install, or a
// config the backend is about to rewrite).
function readConfigTarget() {
  try {
    const cfg = JSON.parse(readFileSync(configPath, 'utf-8'));
    const port = cfg?.server?.port;
    if (!Number.isInteger(port) || port <= 0 || port > 65535) return null;
    const listenIp = cfg?.server?.listenIp;
    const host =
      listenIp === '0.0.0.0' || listenIp === '::' ? '127.0.0.1' : (listenIp ?? '127.0.0.1');
    return { host, port };
  } catch {
    return null;
  }
}

function readPidfile() {
  try {
    return Number.parseInt(readFileSync(pidfilePath, 'utf-8').trim(), 10);
  } catch {
    return null;
  }
}

function writePidfile(pid) {
  // A failed spawn yields pid === undefined — never persist that.
  if (!Number.isInteger(pid)) return;
  mkdirSync(sloponDir, { recursive: true });
  writeFileSync(pidfilePath, `${pid}\n`);
}

function isPidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    // EPERM means the process exists but belongs to someone else.
    return err?.code === 'EPERM';
  }
}

// <install>/node-runtime wins over the starting node so a bundled runtime is
// used even when launcher.mjs is run via a system node by hand.
function resolveNode() {
  const candidate = IS_WIN
    ? path.join(installRoot, 'node-runtime', 'node.exe')
    : path.join(installRoot, 'node-runtime', 'bin', 'node');
  return existsSync(candidate) ? candidate : process.execPath;
}

function spawnBackend(nodeBin) {
  mkdirSync(logsDir, { recursive: true });
  appendFileSync(backendLogPath, `\n===== ${new Date().toISOString()} launcher session =====\n`);
  const outFd = openSync(backendLogPath, 'a');
  const child = spawn(nodeBin, [path.join(installRoot, 'backend', 'index.js')], {
    cwd: path.join(installRoot, 'backend'),
    detached: true,
    stdio: ['ignore', outFd, outFd],
    windowsHide: true,
  });
  child.unref();
  // Spawn failures (missing binary, EACCES) arrive asynchronously — the
  // readiness loop checks the flag instead of relying on a throw here.
  let spawnFailed = false;
  child.once('error', (err) => {
    spawnFailed = true;
    log(`backend spawn failed: ${err.message}`);
  });
  writePidfile(child.pid);
  log(`backend spawned (pid ${child.pid})`);
  return () => spawnFailed;
}

function spawnGui() {
  const options = { detached: true, stdio: 'ignore', windowsHide: true };
  let child;
  if (IS_WIN) {
    child = spawn(path.join(installRoot, 'frontend', 'slopon_dev.exe'), [], options);
  } else if (IS_MAC) {
    child = spawn('open', [path.join(installRoot, 'frontend', 'slopon_dev.app')], options);
  } else {
    child = spawn(path.join(installRoot, 'frontend', 'slopon_dev'), [], options);
  }
  child.unref();
  // The spawn is fire-and-forget, but an EXECUTION failure (missing binary,
  // antivirus quarantine) must not vanish as an unhandled 'error' event.
  child.once('error', (err) => log(`GUI spawn failed: ${err.message}`));
  log('GUI launched');
}

// Single shared budget covering fresh-install config appearance + TCP accept.
async function awaitReadiness(initialTarget, isSpawnFailed) {
  const deadline = Date.now() + READY_BUDGET_MS;
  let target = initialTarget;
  while (Date.now() < deadline) {
    if (isSpawnFailed()) {
      throw new Error(`backend spawn failed — see ${backendLogPath}`);
    }
    if (target === null) {
      target = readConfigTarget(); // appears during the backend's first boot
    }
    if (target !== null && (await probeTcp(target.host, target.port))) {
      return target;
    }
    await sleep(POLL_MS);
  }
  const where = target === null ? 'config.json never provisioned' : `${target.host}:${target.port} never accepted`;
  throw new Error(`backend not ready within ${READY_BUDGET_MS / 1000}s (${where}) — see ${backendLogPath}`);
}

async function start() {
  let target = readConfigTarget();
  const pid = readPidfile();

  if (target === null && pid !== null && isPidAlive(pid)) {
    // A live backend exists but its config is not readable yet — wait for the
    // file before probing (same budget as the readiness phase).
    const deadline = Date.now() + READY_BUDGET_MS;
    while (Date.now() < deadline && target === null) {
      await sleep(POLL_MS);
      target = readConfigTarget();
    }
    if (target === null) {
      throw new Error(`backend (pid ${pid}) is running but ${configPath} did not appear`);
    }
  }

  if (target !== null) {
    const listening = await probeTcp(target.host, target.port);
    if (listening) {
      if (pid !== null && isPidAlive(pid)) {
        log(`backend already running (pid ${pid}) on ${target.host}:${target.port}`);
      } else {
        log(`warning: ${target.host}:${target.port} is listening without a live pidfile — backend was started manually or by an unknown listener; not spawning a second one`);
      }
      spawnGui();
      return;
    }
  }

  const isSpawnFailed = spawnBackend(resolveNode());
  const ready = await awaitReadiness(target, isSpawnFailed);
  log(`backend ready on ${ready.host}:${ready.port}`);
  spawnGui();
}

async function stop() {
  const pid = readPidfile();
  if (pid === null) {
    log('--stop: no pidfile — backend is not running (or was started manually)');
    console.log('No SlopOn backend pidfile found — nothing to stop.');
    return;
  }
  if (!isPidAlive(pid)) {
    rmSync(pidfilePath, { force: true });
    log(`--stop: removed stale pidfile (pid ${pid})`);
    console.log('Removed a stale SlopOn pidfile.');
    return;
  }

  log(`--stop: stopping backend pid ${pid}`);
  if (IS_WIN) {
    // Best-effort tree kill: /T covers the supervised runner child. Node
    // SIGTERM handlers do not run for external kills; SQLite journal/WAL
    // recovery makes the hard kill safe.
    spawnSync('taskkill', ['/PID', String(pid), '/T'], { windowsHide: true, stdio: 'ignore' });
  } else {
    try {
      process.kill(pid, 'SIGTERM');
    } catch (err) {
      log(`--stop: SIGTERM failed (${err.message}) — escalating`);
    }
  }

  const deadline = Date.now() + STOP_GRACE_MS;
  while (Date.now() < deadline && isPidAlive(pid)) {
    await sleep(POLL_MS);
  }
  if (isPidAlive(pid)) {
    log(`--stop: pid ${pid} survived the grace period — force killing`);
    if (IS_WIN) {
      spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
    } else {
      try {
        process.kill(pid, 'SIGKILL');
      } catch (err) {
        log(`--stop: SIGKILL failed: ${err.message}`);
      }
    }
  }

  // Wait for the configured port to actually close before releasing the
  // pidfile — an upgrade re-run depends on the port being free.
  const target = readConfigTarget();
  if (target !== null) {
    const closeDeadline = Date.now() + STOP_GRACE_MS;
    while (Date.now() < closeDeadline && (await probeTcp(target.host, target.port))) {
      await sleep(POLL_MS);
    }
    if (await probeTcp(target.host, target.port)) {
      log(`--stop: warning: ${target.host}:${target.port} still accepts connections (unknown listener?)`);
    }
  }

  rmSync(pidfilePath, { force: true });
  log('--stop: pidfile removed');
  console.log('SlopOn backend stopped.');
}

async function main() {
  try {
    if (process.argv.includes('--stop')) {
      await stop();
      return;
    }
    await start();
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    log(`FATAL: ${message}`);
    fatalDialog(message);
    process.exitCode = 1;
  }
}

await main();
