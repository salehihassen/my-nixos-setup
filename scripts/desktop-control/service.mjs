import net from 'node:net';
import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile as execFileCallback, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { buttonCode, keySequence, outputPoint } from './core.mjs';

const execFile = promisify(execFileCallback);
const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;
const directory = path.join(runtime, 'desktop-control');
const socketPath = path.join(directory, 'control.sock');
const binary = {
  niri: process.env.NIRI_BIN || 'niri',
  grim: process.env.GRIM_BIN || 'grim',
  ydotool: process.env.YDOTOOL_BIN || 'ydotool',
  fuzzel: process.env.FUZZEL_BIN || 'fuzzel',
  crosshair: process.env.CROSSHAIR_BIN || 'desktop-control-crosshair',
  wlrctl: process.env.WLRCTL_BIN || 'wlrctl',
  notify: process.env.NOTIFY_BIN || 'notify-send',
};

async function command(name, args, timeout = 5000) {
  const { stdout } = await execFile(binary[name], args, {
    timeout,
    maxBuffer: 24 * 1024 * 1024,
    encoding: 'buffer',
  });
  return stdout;
}

async function outputs() {
  const raw = JSON.parse((await command('niri', ['msg', '--json', 'outputs'])).toString());
  return Object.entries(raw).map(([name, details]) => ({
    name,
    logical: details.logical,
  }));
}

async function selectedOutput(name) {
  const output = (await outputs()).find((item) => item.name === name);
  if (!output) throw new Error(`Output is unavailable: ${name}`);
  return output;
}

async function showCrosshair(output, x, y) {
  const child = spawn(binary.crosshair, [output, String(x), String(y)], {
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  await new Promise((resolve, reject) => {
    let readyText = '';
    const timer = setTimeout(() => reject(new Error('Crosshair did not appear')), 3000);
    child.stdout.on('data', (data) => {
      readyText += data;
      if (readyText.includes('READY\n')) { clearTimeout(timer); resolve(); }
    });
    child.on('error', (error) => { clearTimeout(timer); reject(error); });
    child.on('exit', (code) => { clearTimeout(timer); reject(new Error(`Crosshair exited: ${code}`)); });
  }).catch((error) => { child.kill('SIGTERM'); throw error; });
  return child;
}

async function approval(description, marker, crosshair) {
  return await new Promise((resolve, reject) => {
    const child = spawn(binary.fuzzel, [
      '--dmenu', '--lines=2', '--minimal-lines',
      ...(marker ? [
        `--output=${marker.output}`,
        `--anchor=${marker.y < marker.height / 2 ? 'bottom' : 'top'}`,
        '--y-margin=20',
      ] : []),
      '--prompt', 'AI desktop action > ', `--mesg=${description.slice(0, 180)}`,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    crosshair?.once('exit', () => child.kill('SIGTERM'));
    let answer = '';
    let errors = '';
    const timer = setTimeout(() => child.kill('SIGTERM'), 60000);
    child.stdout.on('data', (data) => { answer += data; });
    child.stderr.on('data', (data) => { errors += data; });
    child.on('error', reject);
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code !== 0 && errors) return reject(new Error(`Approval prompt failed: ${errors.trim()}`));
      resolve(code === 0 && answer.trim() === 'APPROVE');
    });
    child.stdin.end('DENY\nAPPROVE\n');
  });
}

const buttons = new Set(['left', 'right', 'middle']);
function count(value, label, limit) {
  if (!Number.isInteger(value) || value < 1 || value > limit) {
    throw new Error(`${label} must be between 1 and ${limit}`);
  }
  return value;
}

async function move(point) {
  // wlrctl uses the compositor's virtual-pointer protocol. Reset to the
  // canvas's top-right edge before a relative move to avoid pointer
  // acceleration and ydotool's imprecise "absolute" emulation.
  const all = await outputs();
  const right = Math.max(...all.map((item) => item.logical.x + item.logical.width)) - 1;
  await command('wlrctl', ['pointer', 'move', '100000', '-100000']);
  await command('wlrctl', ['pointer', 'move', String(point.x - right), String(point.y)]);
}

async function perform(request) {
  const { op, args = {} } = request;
  if (op === 'list_outputs') return { outputs: await outputs() };
  if (op === 'screenshot') {
    const output = await selectedOutput(args.output);
    const png = await command('grim', ['-o', output.name, '-'], 12000);
    return { output, mimeType: 'image/png', image: png.toString('base64') };
  }

  let description;
  let action;
  let marker;
  if (op === 'click' || op === 'move') {
    const output = await selectedOutput(args.output);
    const point = outputPoint(output, args.x, args.y);
    const button = args.button || 'left';
    if (!buttons.has(button)) throw new Error('Unsupported mouse button');
    const clicks = op === 'click' ? count(args.clicks || 1, 'clicks', 2) : 0;
    description = `${op} ${op === 'click' ? `${button} ${clicks}x ` : ''}at ${output.name} (${args.x}, ${args.y})`;
    if (op === 'click') marker = { output: output.name, x: args.x, y: args.y, height: output.logical.height };
    action = async () => {
      await move(point);
      for (let i = 0; i < clicks; i++) await command('wlrctl', ['pointer', 'click', button]);
    };
  } else if (op === 'type_text') {
    if (typeof args.text !== 'string' || !args.text.length || args.text.length > 1000 || args.text.includes('\0')) {
      throw new Error('text must contain 1–1000 characters and no NUL');
    }
    description = `type ${JSON.stringify(args.text).slice(0, 130)}`;
    action = () => command('ydotool', ['type', '--', args.text], 12000);
  } else if (op === 'key_combo') {
    const sequence = keySequence(args.keys);
    description = `press ${args.keys.join('+')}`;
    action = () => command('ydotool', ['key', ...sequence]);
  } else if (op === 'scroll') {
    const output = await selectedOutput(args.output);
    const point = outputPoint(output, args.x, args.y);
    const amount = args.amount;
    if (!Number.isInteger(amount) || amount < -10 || amount > 10 || amount === 0) {
      throw new Error('amount must be -10 through 10, excluding zero');
    }
    description = `scroll ${amount} steps at ${output.name} (${args.x}, ${args.y})`;
    action = async () => {
      await move(point);
      await command('wlrctl', ['pointer', 'scroll', String(amount * 120), '0']);
    };
  } else if (op === 'drag') {
    const output = await selectedOutput(args.output);
    const start = outputPoint(output, args.fromX, args.fromY);
    const end = outputPoint(output, args.toX, args.toY);
    description = `drag on ${output.name} (${args.fromX}, ${args.fromY}) to (${args.toX}, ${args.toY})`;
    action = async () => {
      await move(start);
      await command('ydotool', ['click', buttonCode('left', 'down')]);
      try {
        for (let step = 1; step <= 10; step++) {
          await move({
            x: Math.round(start.x + (end.x - start.x) * step / 10),
            y: Math.round(start.y + (end.y - start.y) * step / 10),
          });
          await new Promise((resolve) => setTimeout(resolve, 20));
        }
      } finally {
        await command('ydotool', ['click', buttonCode('left', 'up')]);
      }
    };
  } else {
    throw new Error(`Unknown operation: ${op}`);
  }

  const crosshair = marker ? await showCrosshair(marker.output, marker.x, marker.y) : null;
  let approved;
  try { approved = await approval(description, marker, crosshair); }
  finally { crosshair?.kill('SIGTERM'); }
  if (!approved) return { approved: false, message: 'Action denied or timed out' };
  await new Promise((resolve) => setTimeout(resolve, 180));
  await action();
  return { approved: true, message: description };
}

await fs.mkdir(directory, { recursive: true, mode: 0o700 });
await fs.rm(socketPath, { force: true });
let queue = Promise.resolve();
const server = net.createServer((client) => {
  let input = '';
  client.setTimeout(75000, () => client.destroy());
  client.on('data', (chunk) => {
    input += chunk.toString();
    if (input.length > 65536) { client.destroy(); return; }
    const newline = input.indexOf('\n');
    if (newline < 0) return;
    const line = input.slice(0, newline);
    client.removeAllListeners('data');
    queue = queue.then(async () => {
      try {
        const result = await perform(JSON.parse(line));
        client.end(JSON.stringify({ ok: true, result }) + '\n');
      } catch (error) {
        client.end(JSON.stringify({ ok: false, error: error.message }) + '\n');
      }
    });
  });
});
server.listen(socketPath, async () => {
  await fs.chmod(socketPath, 0o600);
  try { await command('notify', ['AI desktop control enabled', 'Input actions require approval. Mod+BackSpace stops control.']); }
  catch { /* Notification delivery is optional; the socket remains ready. */ }
});
