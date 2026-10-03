import { readdirSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

function option(args, short, long) {
  for (let i = 1; i < args.length; i++) {
    if (args[i] === short || args[i] === long) return args[i + 1] ?? null;
    if (args[i].startsWith(`${long}=`)) return args[i].slice(long.length + 1);
    if (args[i].startsWith(short) && args[i].length > short.length) {
      return args[i].slice(short.length);
    }
  }
  return null;
}

// Read the live process, rather than keeping state that could survive a crash.
export function readRecordings(procRoot = '/proc', uid = process.getuid()) {
  const recordings = [];
  for (const pid of readdirSync(procRoot)) {
    if (!/^\d+$/.test(pid)) continue;
    const directory = `${procRoot}/${pid}`;
    try {
      if (statSync(directory).uid !== uid) continue;
      if (readFileSync(`${directory}/comm`, 'utf8').trim() !== 'wf-recorder') continue;
      if (/^State:\s+[ZX]/m.test(readFileSync(`${directory}/status`, 'utf8'))) continue;
      const args = readFileSync(`${directory}/cmdline`, 'utf8').split('\0').filter(Boolean);
      if (args.length === 0) continue;
      recordings.push({
        pid: Number(pid),
        output: option(args, '-o', '--output'),
        file: option(args, '-f', '--file'),
      });
    } catch (error) {
      // Processes can exit between reads. Other errors must not look like idle.
      if (!['ENOENT', 'ESRCH', 'EACCES'].includes(error.code)) throw error;
    }
  }
  return recordings;
}

export function screenLabel(output, outputs) {
  if (!output) return 'Unknown screen';
  if (/^eDP-/.test(output)) return `Laptop (${output})`;
  const model = outputs[output]?.model;
  return model ? `${model} (${output})` : output;
}

if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  const recordings = readRecordings();
  let outputs = {};
  if (recordings.length > 0) {
    try {
      outputs = JSON.parse(execFileSync('niri', ['msg', '--json', 'outputs'], {
        encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'pipe'],
      }));
    } catch {
      // Keep showing recording and its connector if the compositor is unavailable.
    }
  }
  console.log(JSON.stringify(recordings.map(recording => ({
    ...recording, screen: screenLabel(recording.output, outputs),
  }))));
}
