import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { JsonStream, updateGraph, startMonitor } from '../dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/monitor.mjs';

const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(predicate, message) {
  for (let i = 0; i < 200; i++) { if (await predicate()) return; await wait(15); }
  assert.fail(message);
}

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

test('persistent monitor follows Niri and PipeWire changes, reconnects, and stays quiet at idle', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'capture-monitor-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const socketPath = path.join(root, 'niri.sock');
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
  const fifo = path.join(root, 'graph-events');
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
    pwCommand: [process.execPath, '-e', script],
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
