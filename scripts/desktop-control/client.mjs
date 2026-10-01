import net from 'node:net';
import path from 'node:path';

const runtime = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid()}`;
const socketPath = path.join(runtime, 'desktop-control', 'control.sock');

export function request(op, args = {}) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    let input = '';
    let answered = false;
    socket.setTimeout(76000, () => socket.destroy(new Error('Desktop control timed out')));
    socket.on('connect', () => socket.write(JSON.stringify({ op, args }) + '\n'));
    socket.on('data', (chunk) => {
      input += chunk.toString();
      const newline = input.indexOf('\n');
      if (newline < 0) return;
      answered = true;
      socket.end();
      try {
        const message = JSON.parse(input.slice(0, newline));
        if (!message.ok) reject(new Error(message.error));
        else resolve(message.result);
      } catch (error) { reject(error); }
    });
    socket.on('error', (error) => {
      if (error.code === 'ECONNREFUSED' || error.code === 'ENOENT') {
        reject(new Error('Desktop control is stopped. Start it explicitly with systemctl --user start desktop-control.service.'));
      } else reject(error);
    });
    socket.on('close', () => {
      if (!answered) reject(new Error('Desktop control stopped before the action completed.'));
    });
  });
}
