import { spawn } from 'node:child_process';
import { watch } from 'node:fs';
import { readFile, readdir, readlink, realpath } from 'node:fs/promises';
import net from 'node:net';
import path from 'node:path';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';
import { panelStatus, summarize, withCamera } from './status.mjs';

// pw-dump --monitor emits consecutive, pretty-printed JSON arrays. Decode each
// value once, even when it crosses pipe chunks or contains brackets in strings.
export class JsonStream {
  constructor(onValue) { this.onValue = onValue; this.buffer = ''; this.depth = 0; this.quoted = false; this.escaped = false; }
  push(chunk) {
    for (const char of chunk) {
      if (!this.buffer && /\s/.test(char)) continue;
      this.buffer += char;
      if (this.buffer.length > 16 * 1024 * 1024) throw Error('JSON event exceeds size limit');
      if (this.quoted) {
        if (this.escaped) this.escaped = false;
        else if (char === '\\') this.escaped = true;
        else if (char === '"') this.quoted = false;
      } else if (char === '"') this.quoted = true;
      else if (char === '[' || char === '{') this.depth++;
      else if (char === ']' || char === '}') {
        if (--this.depth === 0) {
          const value = JSON.parse(this.buffer);
          this.buffer = '';
          this.onValue(value);
        }
      } else if (this.depth === 0) throw Error('Expected a JSON object or array');
    }
  }
}

export function updateGraph(graph, batch) {
  if (!Array.isArray(batch)) throw Error('Invalid PipeWire batch');
  for (const item of batch) {
    if (item.info === null) { graph.delete(item.id); continue; }
    const previous = graph.get(item.id);
    // pw-dump sends partial info updates. A changed object type means its ID
    // was reused and must not inherit the previous object's properties.
    const old = !item.type || item.type === previous?.type ? previous : undefined;
    const type = item.type ?? old?.type;
    if (!/^PipeWire:Interface:(Node|Link|Client)$/.test(type ?? '')) { graph.delete(item.id); continue; }
    graph.set(item.id, { ...old, ...item, type, info: { ...old?.info, ...item.info } });
  }
}

// Read only descriptors visible to the desktop user, only after camera events.
// Looking at /proc symlinks never opens the video device or reads its frames.
export async function cameraUsers(cameras, procRoot = '/proc') {
  const devices = new Set(cameras);
  const users = [];
  if (!devices.size) return users;
  for (const pid of await readdir(procRoot)) {
    if (!/^\d+$/.test(pid)) continue;
    let descriptors;
    try { descriptors = await readdir(path.join(procRoot, pid, 'fd')); }
    catch (error) {
      if (['ENOENT', 'ESRCH', 'EACCES', 'EPERM'].includes(error.code)) continue;
      throw error;
    }
    const opened = new Set();
    await Promise.all(descriptors.map(async fd => {
      try {
        const device = await readlink(path.join(procRoot, pid, 'fd', fd));
        if (devices.has(device)) opened.add(device);
      } catch (error) {
        if (!['ENOENT', 'ESRCH', 'EACCES', 'EPERM', 'EINVAL'].includes(error.code)) throw error;
      }
    }));
    if (!opened.size) continue;
    let app;
    try { app = (await readFile(path.join(procRoot, pid, 'comm'), 'utf8')).trim(); }
    catch (error) { if (['ENOENT', 'ESRCH'].includes(error.code)) continue; throw error; }
    if (/^(pipewire(?:-pulse)?|wireplumber)$/.test(app)) continue;
    for (const device of opened) users.push({ pid, app, device });
  }
  return users.sort((a, b) => a.pid.localeCompare(b.pid) || a.device.localeCompare(b.device));
}

export function watchCameras(onChange, {
  devRoot = '/dev', sysRoot = '/sys/class/video4linux', procRoot = '/proc',
  inotifyCommand = ['inotifywait'], debounceMs = 100, retryMs = 1000,
} = {}) {
  let stopped = false, child, directory, timer, retry, generation = 0;
  let running = false, dirty = false, cameras = [];
  const later = () => {
    clearTimeout(retry);
    if (!stopped) retry = setTimeout(setup, Math.min(retryMs *= 2, 30000));
  };
  const scan = async () => {
    if (stopped) return;
    if (running) { dirty = true; return; }
    running = true;
    const version = generation;
    try {
      const users = await cameraUsers(cameras, procRoot);
      if (!stopped && version === generation) onChange(users);
    } catch { if (!stopped && version === generation) onChange(null); }
    finally {
      running = false;
      if (dirty) { dirty = false; schedule(); }
    }
  };
  const schedule = () => {
    if (stopped || timer) return;
    timer = setTimeout(() => { timer = null; void scan(); }, debounceMs);
  };
  const setup = async () => {
    const version = ++generation;
    clearTimeout(retry);
    clearTimeout(timer); timer = null; dirty = false;
    child?.kill(); child = null;
    // Unknown until inotify confirms the watches exist, then scan descriptors
    // that were already open before the monitor started.
    onChange(null);
    try {
      if (!directory) {
        directory = watch(devRoot, (_event, name) => {
          if (/^video\d+$/.test(String(name))) void setup();
        });
        directory.on('error', () => {
          directory?.close(); directory = null;
          ++generation; child?.kill(); child = null;
          onChange(null); later();
        });
      }
      let names;
      try { names = await readdir(sysRoot); }
      catch (error) { if (error.code === 'ENOENT') names = []; else throw error; }
      const found = (await Promise.all(names.filter(n => /^video\d+$/.test(n)).map(async name => {
        try { return (await readFile(path.join(sysRoot, name, 'index'), 'utf8')).trim() === '0' ? path.join(devRoot, name) : null; }
        catch (error) { if (error.code === 'ENOENT') return null; throw error; }
      }))).filter(Boolean);
      if (stopped || version !== generation) return;
      cameras = found;
      if (!cameras.length) { onChange([]); return; }
      const watcher = spawn(inotifyCommand[0], [...inotifyCommand.slice(1), '--monitor', '--event', 'open,close,delete_self,move_self', '--format', '%e', ...cameras], {
        stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, LC_ALL: 'C' },
      });
      child = watcher;
      let ready = false;
      createInterface({ input: watcher.stderr }).on('line', line => {
        if (stopped || version !== generation) return;
        if (line.includes('Watches established.')) { ready = true; retryMs = 1000; schedule(); }
      });
      createInterface({ input: watcher.stdout }).on('line', line => {
        if (stopped || version !== generation) return;
        if (/DELETE_SELF|MOVE_SELF|IGNORED|Q_OVERFLOW/.test(line)) void setup();
        else if (ready) schedule();
      });
      const failed = () => {
        if (stopped || version !== generation) return;
        ++generation; child = null;
        onChange(null); later();
      };
      watcher.once('error', failed);
      watcher.once('exit', failed);
    } catch {
      if (!stopped && version === generation) { onChange(null); later(); }
    }
  };
  void setup();
  return () => {
    stopped = true; ++generation;
    clearTimeout(timer); clearTimeout(retry);
    directory?.close(); child?.kill();
  };
}

function request(socketPath, command) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const timer = setTimeout(() => socket.destroy(Error('Niri request timed out')), 3000);
    const lines = createInterface({ input: socket });
    socket.once('connect', () => socket.write(JSON.stringify(command) + '\n'));
    socket.once('error', reject);
    socket.once('close', () => { clearTimeout(timer); reject(Error('Niri request closed')); });
    lines.once('line', line => {
      try {
        const response = JSON.parse(line);
        if (!response.Ok || !(command in response.Ok)) throw Error('Niri request failed');
        resolve(response.Ok[command]);
      } catch (error) { reject(error); }
      finally { socket.destroy(); }
    });
  });
}

export function startMonitor({
  socketPath = process.env.NIRI_SOCKET,
  emit = status => process.stdout.write(JSON.stringify(status) + '\n'),
  pwCommand = ['pw-dump', '--monitor', '--no-colors'],
  cameraOptions = {}, debounceMs = 75, retryMs = 1000,
} = {}) {
  if (!socketPath) throw Error('NIRI_SOCKET is missing; start the monitor inside the Niri session');
  let stopped = false, socket, pipewire, publishTimer, niriRetry, pwRetry;
  let casts = null, windows = new Map(), outputs = {}, users = null, pipewireReady = false;
  let last = '', niriGeneration = 0, pwGeneration = 0, outputNames = '';
  let niriDelay = retryMs, pwDelay = retryMs;
  const graph = new Map(), processNames = {};
  const publish = () => {
    publishTimer = null;
    if (stopped) return;
    let status = casts === null ? {
      text: 'Capture status unavailable', tone: 'error', captures: [],
      tooltip: 'Niri event connection unavailable. Capture may still be running.',
    } : summarize({ casts, windows: [...windows.values()], outputs, graph: [...graph.values()], processNames });
    if (casts?.length && !pipewireReady) {
      if (casts.some(cast => cast.is_active)) status.tooltip += '\nPipeWire consumer information is unavailable.';
      else status = { text: 'Capture status unavailable', tone: 'error', captures: [], tooltip: 'Retained Niri casts cannot be attributed while PipeWire is unavailable.' };
    }
    const value = JSON.stringify(panelStatus(withCamera(status, users)));
    if (value !== last) { last = value; emit(JSON.parse(value)); }
  };
  const changed = () => { if (!stopped && !publishTimer) publishTimer = setTimeout(publish, debounceMs); };
  const refreshOutputs = async version => {
    try {
      const value = await request(socketPath, 'Outputs');
      if (!stopped && version === niriGeneration) { outputs = value; changed(); }
    } catch { /* Preserve connector IDs when display metadata is unavailable. */ }
  };
  const connectNiri = () => {
    if (stopped) return;
    const version = ++niriGeneration;
    casts = null; windows.clear(); outputs = {}; outputNames = ''; changed();
    socket = net.createConnection(socketPath);
    const current = socket;
    const lines = createInterface({ input: current });
    current.once('connect', () => current.write('"EventStream"\n'));
    lines.on('line', async line => {
      if (stopped || version !== niriGeneration) return;
      try {
        const event = JSON.parse(line);
        if (event.Err) throw Error('Niri rejected event stream');
        if (event.CastsChanged) {
          casts = event.CastsChanged.casts;
          if (!Array.isArray(casts)) throw Error('Invalid casts event');
          niriDelay = retryMs;
          for (const pid of Object.keys(processNames)) delete processNames[pid];
          const pending = casts;
          changed();
          await Promise.all(pending.filter(cast => cast.pid != null).map(async cast => {
            try {
              const name = (await readFile(`/proc/${cast.pid}/comm`, 'utf8')).trim();
              if (version === niriGeneration && casts === pending) processNames[cast.pid] = name;
            } catch { /* The consumer may have exited. */ }
          }));
          changed();
        } else if (event.WindowsChanged) {
          windows = new Map(event.WindowsChanged.windows.map(window => [window.id, window]));
          changed();
        } else if (event.WindowOpenedOrChanged) {
          const window = event.WindowOpenedOrChanged.window;
          windows.set(window.id, window);
          if (casts?.some(cast => cast.target?.Window?.id === window.id)) changed();
        } else if (event.WindowClosed) {
          windows.delete(event.WindowClosed.id); changed();
        } else if (event.WorkspacesChanged) {
          const names = JSON.stringify([...new Set(event.WorkspacesChanged.workspaces.map(ws => ws.output).filter(Boolean))].sort());
          if (names !== outputNames) { outputNames = names; void refreshOutputs(version); }
        } else if (event.ConfigLoaded) void refreshOutputs(version);
      } catch { current.destroy(); }
    });
    current.on('error', () => {});
    current.once('close', () => {
      lines.close();
      if (stopped || version !== niriGeneration) return;
      casts = null; changed();
      niriRetry = setTimeout(connectNiri, niriDelay);
      niriDelay = Math.min(niriDelay * 2, 30000);
    });
  };
  const connectPipeWire = () => {
    if (stopped) return;
    const version = ++pwGeneration;
    graph.clear(); pipewireReady = false; changed();
    const current = spawn(pwCommand[0], pwCommand.slice(1), { stdio: ['ignore', 'pipe', 'ignore'] });
    pipewire = current;
    const parser = new JsonStream(batch => {
      updateGraph(graph, batch); pipewireReady = true; pwDelay = retryMs; changed();
    });
    current.stdout.setEncoding('utf8');
    current.stdout.on('data', chunk => {
      if (stopped || version !== pwGeneration) return;
      try { parser.push(chunk); } catch { current.kill(); }
    });
    const failed = () => {
      if (stopped || version !== pwGeneration) return;
      ++pwGeneration; pipewireReady = false; graph.clear(); changed();
      pwRetry = setTimeout(connectPipeWire, pwDelay);
      pwDelay = Math.min(pwDelay * 2, 30000);
    };
    current.once('error', failed); current.once('exit', failed);
  };
  const stopCamera = watchCameras(value => { users = value; changed(); }, cameraOptions);
  connectNiri(); connectPipeWire();
  return () => {
    stopped = true; ++niriGeneration; ++pwGeneration;
    clearTimeout(publishTimer); clearTimeout(niriRetry); clearTimeout(pwRetry);
    socket?.destroy(); pipewire?.kill(); stopCamera();
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(await realpath(process.argv[1])).href) {
  if (process.argv.includes('--help')) {
    console.log('Usage: capture-target-monitor\nStreams capture-status changes as JSON lines. Read-only; never takes screenshots or opens cameras.');
  } else {
    const stop = startMonitor();
    process.once('exit', stop);
    const shutdown = () => { stop(); process.exitCode = 0; };
    process.once('SIGTERM', shutdown); process.once('SIGINT', shutdown);
    process.stdout.once('error', shutdown);
  }
}
