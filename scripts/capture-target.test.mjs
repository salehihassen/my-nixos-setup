import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cameraUsers, castConsumers, monitorLabel, panelStatus, summarize, withCamera } from '../dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/status.mjs';

const node = (id, props) => ({ id, type: 'PipeWire:Interface:Node', info: { props } });
const client = (id, binary, name) => ({
  id, type: 'PipeWire:Interface:Client',
  info: { props: { 'application.process.binary': binary, 'application.name': name } },
});
const link = (id, output, input) => ({
  id, type: 'PipeWire:Interface:Link',
  info: { 'output-node-id': output, 'input-node-id': input },
});
const cast = (stream_id, target, pw_node_id, is_active = true) => ({
  stream_id, target, pw_node_id, is_active, kind: 'PipeWire', pid: null,
});

test('monitor aliases follow physical identities, with unfamiliar and missing-metadata fallbacks', () => {
  const outputs = {
    'DP-7': { make: 'Acer Technologies', model: 'KB272', serial: '0x12505FA0' },
    'DVI-I-1': { make: 'Dell Inc.', model: 'DELL P2717H', serial: '662C1887M4GL' },
    'DVI-I-9': { make: 'DLOGIC Ltd.', model: 'No Monitor', serial: 'USB_6000-4310' },
    'DP-2': { make: 'Acer Technologies', model: 'KB272', serial: 'office' },
    'DP-3': { make: 'HP', model: 'Z27' },
  };
  assert.equal(monitorLabel('eDP-1', {}), 'built-in (eDP-1)');
  assert.equal(monitorLabel('DP-7', outputs), 'middle (DP-7)');
  assert.equal(monitorLabel('DVI-I-1', outputs), 'right (DVI-I-1)');
  assert.equal(monitorLabel('DVI-I-9', outputs), 'middle (DVI-I-9)');
  assert.equal(monitorLabel('DP-2', outputs), 'KB272 (DP-2)');
  assert.equal(monitorLabel('DP-3', outputs), 'Z27 (DP-3)');
  assert.equal(monitorLabel('DP-4', {}), 'DP-4');
});

test('simultaneous recorder and browser captures keep their own targets', () => {
  const graph = [
    node(11, { 'media.class': 'Video/Source' }),
    node(12, { 'media.class': 'Video/Source' }),
    node(21, { 'client.id': 31 }), node(22, { 'client.id': 32 }),
    client(31, 'gpu-screen-recorder', 'GPU Screen Recorder'),
    client(32, 'chromium', 'Chromium'),
    link(41, 11, 21), link(42, 12, 22),
  ];
  const status = summarize({
    casts: [cast(2, { Window: { id: 154 } }, 12), cast(1, { Output: { name: 'eDP-1' } }, 11)],
    windows: [{ id: 154, title: '~/ai' }, { id: 999, title: 'Focused but not shared' }],
    graph,
  });
  assert.equal(status.text, 'REC · built-in (eDP-1) | SHARE · window: ~/ai (#154)');
  assert.equal(status.tone, 'recording');
  assert.match(status.tooltip, /App: GPU Screen Recorder; cast: 1/);
  assert.match(status.tooltip, /App: Chromium; cast: 2/);
  assert.doesNotMatch(status.text, /Focused/);
});

test('a recorder elsewhere in the graph never turns an unrelated cast into REC', () => {
  const status = summarize({
    casts: [cast(1, { Output: { name: 'DP-1' } }, 11)],
    graph: [node(11, { 'media.class': 'Video/Source' }), client(90, 'gpu-screen-recorder', 'Recorder')],
  });
  assert.equal(status.text, 'CAST · DP-1');
  assert.match(status.tooltip, /consumer unavailable/);
});

test('source IDs reused by clients or audio nodes are not mistaken for video consumers', () => {
  for (const source of [client(11, 'chromium', 'Chromium'), node(11, { 'media.class': 'Stream/Output/Audio' })]) {
    assert.deepEqual(castConsumers(cast(1, {}, 11), [source, node(21, {}), link(41, 11, 21)]), []);
  }
});

test('paused casts do not claim active recording, and unknown targets are explicit', () => {
  assert.equal(summarize({ casts: [] }).text, 'No active capture');
  const paused = summarize({ casts: [cast(1, { Window: { id: 55 } }, 11, false)] });
  assert.equal(paused.text, 'No active capture');
  assert.match(paused.tooltip, /inactive\/paused/);
  assert.equal(summarize({ casts: [cast(1, { Nothing: {} }, null)] }).text, 'CAST · target unavailable');
  assert.equal(summarize({ casts: [cast(1, { Window: { id: 55 } }, null)] }).text,
    'CAST · window: title unavailable (#55)');
});

test('long titles are compact in the panel and complete in the tooltip; IDs remain visible', () => {
  const title = 'A very long window title with Unicode 🐱 and\na second line';
  const status = summarize({ casts: [cast(1, { Window: { id: 55 } }, null)], windows: [{ id: 55, title }] });
  assert.match(status.text, /… \(#55\)$/);
  assert.match(status.tooltip, /Unicode 🐱 and a second line \(#55\)/);
  assert.doesNotMatch(status.text, /\n/);
});

test('wlr consumer PID, shared sources, and link-property fallback are supported', () => {
  const wlr = { ...cast(1, { Output: { name: 'eDP-1' } }, null), pid: 500 };
  assert.equal(summarize({ casts: [wlr], processNames: { 500: 'gpu-screen-recorder' } }).text,
    'REC · built-in (eDP-1)');
  const graph = [
    node(11, { 'media.class': 'Video/Source' }),
    node(21, { 'application.process.binary': 'gpu-screen-recorder', 'application.name': 'Recorder' }),
    node(22, { 'application.process.binary': 'firefox', 'application.name': 'Firefox' }),
    { id: 41, type: 'PipeWire:Interface:Link', info: { props: { 'link.output.node': '11', 'link.input.node': '21' } } },
    link(42, 11, 22),
  ];
  assert.equal(summarize({ casts: [cast(1, { Output: { name: 'eDP-1' } }, 11)], graph }).text,
    'REC+SHARE · built-in (eDP-1)');
});

test('multiple targets remain discoverable without filling the entire panel', () => {
  const status = summarize({ casts: [1, 2, 3].map(id => cast(id, { Output: { name: `DP-${id}` } }, null)) });
  assert.equal(status.text, 'CAST · DP-1 | CAST · DP-2 | +1 more');
  assert.match(status.tooltip, /DP-3/);
});

test('direct camera ownership excludes mappings and PipeWire, and handles multiple cameras/apps', () => {
  const output = 'p1\ncchromium\nfmem\nn/dev/video4\nf18\nn/dev/video4\nf19\nn/dev/video4\n'
    + 'p2\ncwireplumber\nf20\nn/dev/video0\np3\ncpipewire\nf21\nn/dev/video0\n'
    + 'p4\ncobs\nf22\nn/dev/video0\np5\ncfirefox\nfmem\nn/dev/video4\n';
  assert.deepEqual(cameraUsers(output), [
    { pid: '1', app: 'chromium', device: '/dev/video4' },
    { pid: '4', app: 'obs', device: '/dev/video0' },
  ]);
  assert.deepEqual(cameraUsers(''), []);
});

test('camera remains visible alongside screen sharing, with truthful idle and error states', () => {
  const users = [{ pid: '1', app: 'chromium', device: '/dev/video4' }];
  const idle = summarize({ casts: [] });
  const active = withCamera(idle, users);
  assert.equal(active.text, 'CAM · chromium | No screen capture detected');
  assert.equal(active.tone, 'recording');
  assert.match(active.tooltip, /chromium \(\/dev\/video4; PID 1\)/);
  const share = { text: 'SHARE · window: ~/ai (#154)', tone: 'sharing', tooltip: 'App: Chromium' };
  assert.equal(withCamera(share, users).text, 'CAM · chromium | SHARE · window: ~/ai (#154)');
  assert.equal(withCamera(share, []).text, share.text);
  assert.equal(withCamera(idle, null).tone, 'error');
});

test('a suspended Chromium portal session retains its target without claiming active streaming', () => {
  const graph = [
    node(89, { 'media.class': 'Stream/Output/Video' }),
    node(91, { 'media.class': 'Stream/Input/Video', 'client.id': 85, 'node.target': 89 }),
    client(85, 'chromium', 'chromium'),
  ];
  const snapshot = {
    casts: [cast(33, { Window: { id: 55 } }, 89, false)],
    windows: [{ id: 55, title: 'nixos — screen-recording-panel.md' }], graph,
  };
  const status = summarize(snapshot);
  assert.equal(status.text, 'SHARE (paused) · window: nixos — screen-recording-panel.… (#55)');
  assert.match(status.tooltip, /nixos — screen-recording-panel.md \(#55\)/);
  assert.equal(status.tone, 'sharing');
  assert.match(status.tooltip, /not streaming frames/);
  assert.equal(summarize({ ...snapshot, graph: [client(89, 'chromium', 'chromium'), ...graph.slice(1)] }).text,
    'No active capture');
  assert.equal(summarize({ ...snapshot, graph: [graph[0], { ...graph[1], info: { props: {
    'media.class': 'Stream/Input/Video', 'client.id': 85, 'node.target': 999,
  } } }, graph[2]] }).text, 'No active capture');
});

test('panel text plus an icon and spacing stays below fifteen characters, preserving full hover details', () => {
  const users = [{ pid: '1', app: 'chromium', device: '/dev/video4' }];
  const single = summarize({ casts: [cast(1, { Window: { id: 55 } }, null)], windows: [{ id: 55, title: 'Long editor title 🐱' }] });
  const record = { ...single, captures: [{ prefix: 'REC', active: true, target: 'built-in' }] };
  const paused = { ...single, captures: [{ prefix: 'SHARE', active: false, target: '#55' }] };
  assert.equal(panelStatus(single).text, 'CAST #55');
  assert.equal(panelStatus(record).text, 'REC built-in');
  assert.equal(panelStatus(paused).text, 'PAUSED #55');
  assert.equal(panelStatus(withCamera(paused, users)).text, 'CAM+PAUSED');
  assert.equal(panelStatus(withCamera(summarize({ casts: [] }), users)).text, 'Camera on');
  assert.equal(panelStatus(summarize({ casts: [] })).text, 'Idle');
  const variants = [single, record, paused, summarize({ casts: [1, 2, 3].map(id => cast(id, { Output: { name: `DP-${id}` } }, null)) }),
    summarize({ casts: [cast(1, { Output: { name: 'A very long unfamiliar connector 🐱' } }, null)] }),
    { text: 'Capture status unavailable', tone: 'error', tooltip: 'Could not query Niri' }];
  for (const variant of variants) {
    for (const camera of [[], users, null]) {
      const full = withCamera(variant, camera);
      const compact = panelStatus(full);
      assert.ok(Array.from(compact.text).length + 2 < 15, compact.text);
      assert.equal(compact.tooltip, full.tooltip);
    }
  }
  assert.match(panelStatus(single).tooltip, /Long editor title 🐱 \(#55\)/);
});
