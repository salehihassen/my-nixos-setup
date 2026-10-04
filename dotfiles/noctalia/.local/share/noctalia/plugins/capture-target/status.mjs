import { execFile } from 'node:child_process';
import { readFile, readdir, realpath } from 'node:fs/promises';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

const exec = promisify(execFile);
const aliases = {
  'Acer Technologies KB272 0x12505FA0': 'middle',
  'DLOGIC Ltd. No Monitor USB_6000-4310': 'middle',
  'Dell Inc. DELL P2717H 662C1887M4GL': 'right',
};

function singleLine(value) {
  return String(value ?? '').replace(/\s+/g, ' ').trim();
}

function shorten(value, limit = 32) {
  const chars = Array.from(value);
  return chars.length > limit ? chars.slice(0, limit - 1).join('') + '…' : value;
}

export function monitorLabel(name, outputs = {}) {
  if (!name) return 'monitor: target unavailable';
  if (/^eDP-/.test(name)) return `built-in (${name})`;
  const monitor = outputs[name] ?? {};
  const identity = [monitor.make, monitor.model, monitor.serial].filter(Boolean).join(' ');
  const label = aliases[identity] || singleLine(monitor.model);
  return label ? `${label} (${name})` : name;
}

function targetLabel(target, outputs, windows, compact) {
  if (target?.Output) return monitorLabel(target.Output.name, outputs);
  if (target?.Window) {
    const id = target.Window.id;
    const window = windows.find(item => item.id === id);
    const title = singleLine(window?.title) || singleLine(window?.app_id) || 'title unavailable';
    return `window: ${compact ? shorten(title) : title} (#${id})`;
  }
  return 'target unavailable';
}

function panelTarget(target, outputs) {
  if (target?.Window) return `#${target.Window.id}`;
  if (target?.Output?.name) {
    const name = target.Output.name;
    const alias = monitorLabel(name, outputs).split(' (')[0];
    return ['built-in', 'middle', 'right'].includes(alias) ? alias : name;
  }
  return '?';
}

function consumer(props = {}) {
  const binary = singleLine(props['application.process.binary']);
  const name = singleLine(props['application.name']) || binary;
  return name || binary ? { name, binary } : null;
}

// Follow each cast's source-node links to its consumers. Never attribute a cast
// from the mere presence of a browser/recorder elsewhere in the PipeWire graph.
export function castConsumers(cast, graph = [], processNames = {}) {
  if (cast.pid != null) {
    const binary = processNames[cast.pid];
    return binary ? [{ name: binary, binary }] : [];
  }
  if (cast.pw_node_id == null) return [];
  const objects = new Map(graph.map(object => [Number(object.id), object]));
  const source = objects.get(Number(cast.pw_node_id));
  if (source?.type !== 'PipeWire:Interface:Node') return [];
  const mediaClass = source.info?.props?.['media.class'];
  if (mediaClass && !mediaClass.includes('Video')) return [];

  const found = [];
  for (const link of graph) {
    if (link.type !== 'PipeWire:Interface:Link') continue;
    const props = link.info?.props ?? {};
    const output = link.info?.['output-node-id'] ?? props['link.output.node'];
    if (Number(output) !== Number(cast.pw_node_id)) continue;
    const input = link.info?.['input-node-id'] ?? props['link.input.node'];
    const node = objects.get(Number(input));
    if (node?.type !== 'PipeWire:Interface:Node') continue;
    const nodeProps = node.info?.props ?? {};
    const client = objects.get(Number(nodeProps['client.id']));
    const identity = consumer({ ...client?.info?.props, ...nodeProps });
    if (identity && !found.some(item => item.name === identity.name && item.binary === identity.binary)) {
      found.push(identity);
    }
  }
  // Chromium retains its exact node.target while a portal stream is suspended
  // and has no negotiated links. This identifies the selected session only;
  // Niri's is_active still determines whether frames are streaming.
  if (cast.is_active === false) {
    for (const node of graph) {
      const props = node.info?.props ?? {};
      if (node.type !== 'PipeWire:Interface:Node' || props['media.class'] !== 'Stream/Input/Video'
        || props['node.target'] == null || Number(props['node.target']) !== Number(cast.pw_node_id)) continue;
      const client = objects.get(Number(props['client.id']));
      const identity = consumer({ ...client?.info?.props, ...props });
      if (identity && !found.some(item => item.name === identity.name && item.binary === identity.binary)) found.push(identity);
    }
  }
  return found;
}

function purpose(consumers) {
  const recording = consumers.some(item => /gpu-screen-recorder/i.test(`${item.binary} ${item.name}`));
  const sharing = consumers.some(item => /chromium|chrome|firefox|zen(?:\b|-)/i.test(`${item.binary} ${item.name}`));
  return recording && sharing ? 'REC+SHARE' : recording ? 'REC' : sharing ? 'SHARE' : 'CAST';
}

export function summarize({ casts, outputs = {}, windows = [], graph = [], processNames = {} }) {
  const visibleCasts = casts.filter(cast => cast.is_active === true || castConsumers(cast, graph, processNames).length > 0);
  if (visibleCasts.length === 0) {
    const inactive = casts.length ? `\n${casts.length} inactive/paused cast session(s) reported by Niri.` : '';
    return {
      text: 'No active capture', tone: 'idle', captures: [],
      tooltip: 'No monitor or window is currently streaming through Niri.' + inactive,
    };
  }
  const entries = visibleCasts.map(cast => {
    const consumers = castConsumers(cast, graph, processNames);
    const prefix = purpose(consumers);
    const active = cast.is_active === true;
    const label = prefix + (active ? '' : ' (paused)');
    const owner = consumers.map(item => item.name).join(', ') || 'consumer unavailable';
    return {
      prefix, active, target: panelTarget(cast.target, outputs),
      text: `${label} · ${targetLabel(cast.target, outputs, windows, true)}`,
      detail: `${label} · ${targetLabel(cast.target, outputs, windows, false)}\nApp: ${owner}; cast: ${cast.stream_id}`
        + (active ? '' : '\nSession retained; Niri reports it is not streaming frames.'),
    };
  }).sort((a, b) => Number(b.active) - Number(a.active) || Number(b.prefix.includes('REC')) - Number(a.prefix.includes('REC')));
  const visible = entries.slice(0, 2).map(entry => entry.text).join(' | ');
  return {
    text: visible + (entries.length > 2 ? ` | +${entries.length - 2} more` : ''),
    tone: entries.some(entry => entry.active && entry.prefix.includes('REC')) ? 'recording' : 'sharing',
    captures: entries.map(({ prefix, active, target }) => ({ prefix, active, target })),
    tooltip: entries.map(entry => entry.detail).join('\n\n')
      + '\n\nThis label observes capture targets. Use the recorder icon or Super+Alt+R to control recording.',
  };
}

async function jsonCommand(command, args) {
  const { stdout } = await exec(command, args, { timeout: 1800, maxBuffer: 8 * 1024 * 1024 });
  return JSON.parse(stdout);
}

// lsof supplies process/device ownership without opening the camera ourselves.
// Ignore memory mappings and PipeWire's device ownership: the stock privacy
// widget already detects actual capture through PipeWire links.
export function cameraUsers(output) {
  const users = [];
  let pid, app, descriptor = false;
  for (const line of output.split('\n')) {
    if (line.startsWith('p')) { pid = line.slice(1); app = ''; descriptor = false; }
    else if (line.startsWith('c')) app = singleLine(line.slice(1));
    else if (line.startsWith('f')) descriptor = /^f\d+$/.test(line);
    else if (line.startsWith('n') && descriptor && /^\/dev\/video\d+$/.test(line.slice(1))
      && app && !/^(pipewire(?:-pulse)?|wireplumber)$/.test(app)) {
      const device = line.slice(1);
      if (!users.some(user => user.pid === pid && user.device === device)) users.push({ pid, app, device });
    }
  }
  return users;
}

async function readCameraUsers() {
  let devices;
  try { devices = await readdir('/sys/class/video4linux'); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
  // UVC index 0 is the capture endpoint; index 1 is usually metadata.
  const cameras = (await Promise.all(devices.filter(name => /^video\d+$/.test(name)).map(async name => {
    try { return (await readFile(`/sys/class/video4linux/${name}/index`, 'utf8')).trim() === '0' ? `/dev/${name}` : null; }
    catch { return null; } // Device may have been unplugged during the scan.
  }))).filter(Boolean);
  if (!cameras.length) return [];
  try {
    const { stdout } = await exec('lsof', ['-n', '-w', '-Fpcfn', ...cameras], { timeout: 1800, maxBuffer: 1024 * 1024 });
    return cameraUsers(stdout);
  } catch (error) {
    // lsof returns 1 when any requested device has no open descriptors.
    if (error.code === 1) return cameraUsers(error.stdout || '');
    throw error;
  }
}

export function withCamera(status, users) {
  if (users === null) return {
    ...status, text: `Camera status unavailable | ${status.text}`, tone: 'error', cameraUnavailable: true,
    tooltip: 'Could not check direct camera use.\n\n' + status.tooltip,
  };
  if (!users.length) return status;
  const apps = [...new Set(users.map(user => user.app))].join(', ');
  const capture = status.text === 'No active capture' ? 'No screen capture detected' : status.text;
  return {
    ...status, text: `CAM · ${apps} | ${capture}`, tone: 'recording', cameraActive: true,
    tooltip: users.map(user => `Camera in use: ${user.app} (${user.device}; PID ${user.pid})`).join('\n')
      + '\n\n' + status.tooltip,
  };
}

// Twelve text characters leave room for an adjacent icon and a space while
// keeping the combined indicator under fifteen. Full details stay on hover.
export function panelStatus(status) {
  const captures = status.captures ?? [];
  let text;
  if (captures.length) {
    const active = captures.filter(capture => capture.active);
    const kinds = [...new Set(active.map(capture => capture.prefix))];
    const recording = kinds.some(kind => kind.includes('REC'));
    const sharing = kinds.some(kind => kind.includes('SHARE'));
    const state = active.length === 0 ? 'PAUSED'
      : kinds.length === 1 ? kinds[0] : recording && sharing ? 'REC+SHARE'
      : recording ? 'REC+CAST' : sharing ? 'SHARE+CAST' : 'CAST';
    const cameraState = state.replace('REC+SHARE', 'REC+SHR').replace('SHARE+CAST', 'SHR+CAST');
    text = status.cameraActive ? `CAM+${cameraState}`
      : status.cameraUnavailable ? `CAM? ${state}`
      : captures.length === 1 && state !== 'REC+SHARE' ? `${state} ${captures[0].target}`
      : `${state} x${captures.length}`;
  } else {
    text = status.cameraUnavailable ? 'Camera ?'
      : status.tone === 'error' ? 'Capture ?'
      : status.cameraActive ? 'Camera on' : 'Idle';
    if (status.cameraActive && status.text.includes('Capture status unavailable')) text = 'CAM+Capture?';
  }
  return { ...status, text: shorten(text, 12) };
}

export async function readStatus() {
  const casts = await jsonCommand('niri', ['msg', '--json', 'casts']);
  if (!Array.isArray(casts)) throw new Error('Invalid Niri cast response');
  if (!casts.length) return summarize({ casts });
  const [outputs, windows, graph] = await Promise.allSettled([
    jsonCommand('niri', ['msg', '--json', 'outputs']),
    jsonCommand('niri', ['msg', '--json', 'windows']),
    jsonCommand('pw-dump', []),
  ]);
  const processNames = {};
  await Promise.all(casts.filter(cast => cast.is_active && cast.pid != null).map(async cast => {
    try { processNames[cast.pid] = (await readFile(`/proc/${cast.pid}/comm`, 'utf8')).trim(); } catch {}
  }));
  return summarize({
    casts, processNames,
    outputs: outputs.status === 'fulfilled' ? outputs.value : {},
    windows: windows.status === 'fulfilled' ? windows.value : [],
    graph: graph.status === 'fulfilled' ? graph.value : [],
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(await realpath(process.argv[1])).href) {
  const [capture, camera] = await Promise.allSettled([readStatus(), readCameraUsers()]);
  const status = capture.status === 'fulfilled' ? capture.value : {
      text: 'Capture status unavailable', tone: 'error',
      tooltip: 'Could not query Niri screencasts. Capture may still be running.',
  };
  console.log(JSON.stringify(panelStatus(withCamera(status, camera.status === 'fulfilled' ? camera.value : null))));
}
