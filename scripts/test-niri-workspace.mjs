// Exercise the helper without opening Fuzzel or modifying the live desktop.
// Launcher-mode Fuzzel launches applications and returns no textbox text.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('../dotfiles/misc-scripts/niri-workspace', import.meta.url));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'niri-workspace-test-'));
const stateFile = path.join(temp, 'state.json');
const mock = String.raw`#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const file = process.env.NIRI_WORKSPACE_TEST_STATE;
const state = JSON.parse(fs.readFileSync(file, 'utf8'));
const args = process.argv.slice(2);
let output = '', status = 0;
if (path.basename(process.argv[1]) === 'fuzzel') {
  state.popups.push(args);
  state.popupInputs.push(fs.readFileSync(0, 'utf8'));
  if (args.includes('--dmenu')) {
    const answer = state.answers.shift() ?? {text: ''};
    output = answer.text ?? '';
    status = answer.status ?? 0;
  } else {
    state.launcherInvocations++;
  }
} else if (args[0] === 'msg' && args[1] === 'action') {
  state.actions.push(args.slice(2));
} else if (args.includes('workspaces')) {
  output = JSON.stringify(state.workspacesSequence.length > 1
    ? state.workspacesSequence.shift() : state.workspacesSequence[0]);
} else if (args.includes('outputs')) {
  output = JSON.stringify(state.outputsSequence.length > 1
    ? state.outputsSequence.shift() : state.outputsSequence[0]);
} else if (args.includes('focused-window')) {
  output = JSON.stringify({id: 21});
} else {
  throw new Error('Unexpected command: ' + JSON.stringify(args));
}
fs.writeFileSync(file, JSON.stringify(state));
process.stdout.write(output + '\n');
process.exitCode = status;
`;

const singleOutput = { 'eDP-1': { logical: { x: 0, y: 0, width: 1920, height: 1200 } } };
const twoOutputs = { ...singleOutput, 'DP-1': { logical: { x: 1920, y: 0, width: 1920, height: 1080 } } };

function check(label, mode, {
  name = null, answers = [], actions = [], status = 0, inspect = () => {},
  outputsSequence = [singleOutput], workspacesSequence,
}) {
  fs.writeFileSync(stateFile, JSON.stringify({
    workspacesSequence: workspacesSequence ?? [[
      { id: 1, idx: 1, name, output: 'eDP-1', is_focused: true },
      { id: 2, idx: 2, name: 'project', output: 'eDP-1', is_focused: false },
    ]],
    outputsSequence,
    answers: answers.map(answer => typeof answer === 'string' ? { text: answer } : answer),
    actions: [], popups: [], popupInputs: [], launcherInvocations: 0,
  }));
  const result = spawnSync(helper, [mode], {
    env: { ...process.env, PATH: `${temp}:${process.env.PATH}`, NIRI_WORKSPACE_TEST_STATE: stateFile },
    input: '', encoding: 'utf8',
  });
  const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
  assert.equal(result.status, status, `${label}: ${result.stderr}`);
  assert.equal(state.launcherInvocations, 0, `${label}: textbox must use Fuzzel dmenu mode`);
  assert.deepEqual(state.actions, actions, label);
  inspect(state);
  console.log(`PASS ${label}`);
}

try {
  for (const tool of ['niri', 'fuzzel']) {
    fs.writeFileSync(path.join(temp, tool), mock, { mode: 0o755 });
  }
  check('name an unnamed workspace', 'manage', {
    answers: ['0', 'research'], actions: [['set-workspace-name', '--', 'research']],
  });
  check('rename with current name prefilled', 'manage', {
    name: 'work', answers: ['0', 'research'], actions: [['set-workspace-name', '--', 'research']],
    inspect: state => assert(state.popups[1].includes('work')),
  });
  check('cancel management menu', 'manage', { answers: [{ status: 1 }] });
  check('cancel textbox', 'manage', { answers: ['0', { status: 1 }] });
  check('empty textbox cancels', 'manage', { answers: ['0', '   '] });
  check('explicitly remove name', 'manage', {
    name: 'work', answers: ['1'], actions: [['unset-workspace-name']],
  });
  check('duplicate name rejected', 'manage', { answers: ['0', 'project'], status: 1 });
  check('switch to selected name', 'switch', {
    answers: ['0'], actions: [['focus-workspace', '--', 'project']],
  });
  check('move entire column to selected name', 'move', {
    answers: ['0'], actions: [['move-column-to-workspace', '--', 'project']],
  });
  for (const name of [null, 'work']) {
    check(`hide monitor moves with one display (${name ?? 'unnamed'})`, 'manage', {
      name, answers: [{ status: 1 }],
      inspect: state => {
        assert(!state.popupInputs[0].includes('Move workspace'));
        assert(state.popupInputs[0].includes(name ? 'Rename workspace' : 'Name workspace'));
      },
    });
    for (const [offset, direction] of [[0, 'left'], [1, 'right']]) {
      check(`move ${name ?? 'unnamed'} workspace ${direction}`, 'manage', {
        name, outputsSequence: [twoOutputs], answers: [String((name ? 2 : 1) + offset)],
        actions: [[`move-workspace-to-monitor-${direction}`]],
        inspect: state => {
          assert(state.popupInputs[0].includes('Move workspace to monitor on left'));
          assert(state.popupInputs[0].includes('Move workspace to monitor on right'));
          assert.equal(state.popups.length, 1);
        },
      });
    }
  }
  check('disabled external display does not expose moves', 'manage', {
    outputsSequence: [{ ...singleOutput, 'DP-1': { logical: null, current_mode: null } }],
    answers: [{ status: 1 }],
    inspect: state => assert(!state.popupInputs[0].includes('Move workspace')),
  });
  check('display disconnect cancels move', 'manage', {
    outputsSequence: [twoOutputs, singleOutput], answers: ['1'], status: 1,
    inspect: state => assert(state.popups[1].includes('Another display is no longer available. Please try again.')),
  });
  check('changed focused workspace cancels monitor move', 'manage', {
    outputsSequence: [twoOutputs], answers: ['1'], status: 1,
    workspacesSequence: [
      [{ id: 1, idx: 1, name: null, output: 'eDP-1', is_focused: true }],
      [{ id: 1, idx: 1, name: null, output: 'eDP-1', is_focused: false },
        { id: 2, idx: 2, name: 'project', output: 'eDP-1', is_focused: true }],
    ],
  });
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
