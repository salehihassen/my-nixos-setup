import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { JsonStream, updateGraph, cameraUsers, startMonitor, watchCameras } from '../dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/monitor.mjs';

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, message) {
  for (let i = 0; i < 200; i++) { if (await predicate()) return; await wait(15); }
  assert.fail(message);
}
const inotify = process.env.INOTIFYWAIT || 'inotifywait';
// inotifywait exits with status 1 after printing --help.
const inotifyHelp = spawnSync(inotify, ['--help'], { encoding: 'utf8' });
const hasInotify = !inotifyHelp.error && inotifyHelp.stdout.includes('inotifywait');

test('PipeWire JSON batches survive arbitrary chunks, escaped strings and consecutive values', () => {
  const expected = [[{ id: 1, title: 'brackets [}] and "quote" and 🐱' }], [], [{ id: 2, info: null }]];
  const values = [], parser = new JsonStream(value => values.push(value));
  const input = expected.map(value => JSON.stringify(value, null, 2)).join('\n\n');
  for (let offset = 0; offset < input.length; offset += 3) parser.push(input.slice(offset, offset + 3));
  assert.deepEqual(values, expected);
  assert.throws(() => new JsonStream(() => {}).push('invalid'), /Expected/);
});

test('PipeWire partial updates, removals and reused IDs do not retain stale consumer data', () => {
  const graph = new Map();
  updateGraph(graph, [{ id: 1, type: 'PipeWire:Interface:Node', info: { props: { 'media.class': 'Video/Source' }, state: 'running' } }]);
  updateGraph(graph, [{ id: 1, info: { state: 'suspended' } }]);
  assert.equal(graph.get(1).info.props['media.class'], 'Video/Source');
  assert.equal(graph.get(1).info.state, 'suspended');
  updateGraph(graph, [{ id: 1, type: 'PipeWire:Interface:Client', info: { props: { 'application.name': 'Chromium' } } }]);
  assert.equal(graph.get(1).info.state, undefined);
  assert.equal(graph.get(1).info.props['media.class'], undefined);
  updateGraph(graph, [{ id: 1, info: null }]);
  assert.equal(graph.size, 0);
  updateGraph(graph, [{ id: 1, type: 'PipeWire:Interface:Node', info: { props: {} } }]);
  updateGraph(graph, [{ id: 1, type: 'PipeWire:Interface:Module', info: { props: {} } }]);
  assert.equal(graph.size, 0);
});

test('camera descriptor snapshots ignore mappings, deduplicate FDs, and exclude PipeWire ownership', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'capture-proc-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  for (const [pid, app, targets] of [
    ['1', 'chromium', ['/dev/video0', '/dev/video0', '/tmp/unrelated']],
    ['2', 'pipewire', ['/dev/video0']], ['3', 'wireplumber', ['/dev/video0']],
    ['4', 'obs', ['/dev/video2']], ['5', 'firefox', []],
  ]) {
    await fs.mkdir(path.join(root, pid, 'fd'), { recursive: true });
    await fs.writeFile(path.join(root, pid, 'comm'), app + '\n');
    await fs.writeFile(path.join(root, pid, 'maps'), '/dev/video0');
    for (const [i, target] of targets.entries()) await fs.symlink(target, path.join(root, pid, 'fd', String(i)));
  }
  assert.deepEqual(await cameraUsers(['/dev/video0', '/dev/video2'], root), [
    { pid: '1', app: 'chromium', device: '/dev/video0' },
    { pid: '4', app: 'obs', device: '/dev/video2' },
  ]);
  assert.deepEqual(await cameraUsers([], '/does-not-exist'), []);
});

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'capture-monitor-'));
  const sysRoot = path.join(root, 'sys'), devRoot = path.join(root, 'dev');
  await fs.mkdir(sysRoot); await fs.mkdir(devRoot);
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const addCamera = async name => {
    await fs.mkdir(path.join(sysRoot, name), { recursive: true });
    await fs.writeFile(path.join(sysRoot, name, 'index'), '0\n');
    await fs.writeFile(path.join(devRoot, name), 'fake video endpoint');
    return path.join(devRoot, name);
  };
  return { root, sysRoot, devRoot, addCamera };
}

test('camera watcher reacts to opens/closes and hotplug without idle descriptor rescans', { skip: !hasInotify }, async t => {
  const f = await fixture(t);
  const first = await f.addCamera('video0');
  const states = [];
  const stop = watchCameras(value => states.push(value), { ...f, inotifyCommand: [inotify], debounceMs: 10 });
  t.after(stop);
  await until(() => states.at(-1)?.length === 0, 'camera watcher never became ready');
  const count = states.length;
  await wait(200);
  assert.equal(states.length, count, 'idle cameras should not trigger descriptor scans');
  const fd = await fs.open(first);
  try {
    await until(() => states.at(-1)?.some(user => user.pid === String(process.pid) && user.device === first), 'open camera was not detected');
  } finally { await fd.close(); }
  await until(() => states.at(-1)?.length === 0, 'closed camera stayed active');
  const second = await f.addCamera('video2');
  await until(() => states.length > count + 3 && states.at(-1)?.length === 0, 'hotplug was not observed');
  const fd2 = await fs.open(second);
  try { await until(() => states.at(-1)?.some(user => user.device === second), 'hotplugged camera was not watched'); }
  finally { await fd2.close(); }
  await until(() => states.at(-1)?.length === 0, 'hotplugged camera close was not detected');
  stop();
  const final = states.length;
  await wait(50);
  assert.equal(states.length, final, 'stopped camera watcher published a late result');
});

test('camera already open at monitor startup is discovered after watches are established', { skip: !hasInotify }, async t => {
  const f = await fixture(t), endpoint = await f.addCamera('video0');
  const fd = await fs.open(endpoint), states = [];
  t.after(() => fd.close());
  const stop = watchCameras(value => states.push(value), { ...f, inotifyCommand: [inotify], debounceMs: 10 });
  t.after(stop);
  await until(() => states.at(-1)?.some(user => user.pid === String(process.pid) && user.device === endpoint), 'startup missed an already open camera');
});

test('persistent monitor follows Niri and PipeWire changes, reconnects, and stays quiet at idle', { skip: !hasInotify }, async t => {
  const f = await fixture(t);
  const socketPath = path.join(f.root, 'niri.sock');
  const connections = new Set(), streams = new Set(), statuses = [];
  let casts = [], outputRequests = 0;
  const write = (socket, event) => socket.write(JSON.stringify(event) + '\n');
  const broadcast = event => { for (const socket of streams) write(socket, event); };
  const server = net.createServer(socket => {
    connections.add(socket); socket.on('error', () => {});
    socket.once('close', () => { connections.delete(socket); streams.delete(socket); });
    socket.once('data', data => {
      const command = JSON.parse(data.toString().trim());
      if (command === 'Outputs') {
        outputRequests++;
        write(socket, { Ok: { Outputs: { 'eDP-1': { model: 'Laptop' } } } });
      } else {
        assert.equal(command, 'EventStream'); streams.add(socket);
        write(socket, { Ok: 'Handled' });
        write(socket, { WorkspacesChanged: { workspaces: [{ output: 'eDP-1' }] } });
        write(socket, { WindowsChanged: { windows: [{ id: 42, title: 'Shared editor' }] } });
        write(socket, { CastsChanged: { casts } });
      }
    });
  });
  await new Promise(resolve => server.listen(socketPath, resolve));
  t.after(async () => { for (const socket of connections) socket.destroy(); await new Promise(resolve => server.close(resolve)); });
  const fifo = path.join(f.root, 'graph-events');
  const initialGraph = [
    { id: 11, type: 'PipeWire:Interface:Node', info: { props: { 'media.class': 'Video/Source' } } },
    { id: 21, type: 'PipeWire:Interface:Node', info: { props: { 'application.process.binary': 'chromium', 'node.target': 11, 'media.class': 'Stream/Input/Video' } } },
    { id: 31, type: 'PipeWire:Interface:Link', info: { 'output-node-id': 11, 'input-node-id': 21 } },
  ];
  // A persistent fake PipeWire source watches a fixture file. It emits real
  // pw-dump JSON batches; no running desktop or browser is manipulated.
  await fs.writeFile(fifo, JSON.stringify(initialGraph));
  const script = `const fs=require('node:fs');const p=${JSON.stringify(fifo)};function send(){process.stdout.write(fs.readFileSync(p)+'\\n');}send();fs.watch(p,send);`;
  const stop = startMonitor({ socketPath, emit: status => statuses.push(status),
    pwCommand: [process.execPath, '-e', script], cameraOptions: { ...f, inotifyCommand: [inotify], debounceMs: 10 },
    debounceMs: 10, retryMs: 20 });
  t.after(stop);
  await until(() => statuses.at(-1)?.text === 'Idle', 'initial idle snapshot missing');
  const idle = statuses.length, requests = outputRequests;
  await wait(200);
  assert.equal(statuses.length, idle, 'idle monitor should not republish unchanged status');
  assert.equal(outputRequests, requests, 'idle monitor should not poll Niri');
  casts = [{ stream_id: 1, is_active: true, target: { Window: { id: 42 } }, pw_node_id: 11 }];
  broadcast({ CastsChanged: { casts } });
  await until(() => statuses.at(-1)?.text === 'SHARE #42', 'sharing source attribution missing');
  broadcast({ WindowOpenedOrChanged: { window: { id: 42, title: 'Renamed editor' } } });
  await until(() => statuses.at(-1)?.tooltip.includes('Renamed editor'), 'shared window title did not update');
  casts = [{ ...casts[0], is_active: false }]; broadcast({ CastsChanged: { casts } });
  await until(() => statuses.at(-1)?.text === 'PAUSED #42', 'paused target was lost');
  await fs.writeFile(fifo, 'invalid PipeWire stream');
  await until(() => statuses.at(-1)?.tone === 'error', 'failed PipeWire stream retained a stale consumer');
  await fs.writeFile(fifo, JSON.stringify(initialGraph));
  await until(() => statuses.at(-1)?.text === 'PAUSED #42', 'PipeWire reconnect did not restore attribution');
  await fs.writeFile(fifo, JSON.stringify([{ id: 21, info: null }, { id: 31, info: null }]));
  await until(() => statuses.at(-1)?.text === 'Idle', 'removed consumer stayed visible');
  for (const socket of streams) socket.destroy();
  await until(() => statuses.some(status => status.tone === 'error'), 'disconnect did not expose an unknown state');
  casts = [];
  await until(() => statuses.at(-1)?.text === 'Idle', 'Niri reconnect did not restore state');
  const before = statuses.length;
  stop(); await wait(80);
  assert.equal(statuses.length, before, 'stopped monitor published a late result');
});

test('missing camera watcher is reported as unknown rather than silently claiming idle', async t => {
  const f = await fixture(t); await f.addCamera('video0');
  const states = [];
  const stop = watchCameras(value => states.push(value), { ...f, inotifyCommand: ['/nonexistent/inotifywait'], retryMs: 10000 });
  t.after(stop);
  await wait(100);
  assert.ok(states.length >= 2);
  assert.equal(states.at(-1), null);
});
