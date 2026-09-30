import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const file = path.join(os.homedir(), '.pi/agent/models.json');
const original = fs.readFileSync(file, 'utf8');
const config = JSON.parse(original);
const model = Object.values(config.providers || {})
  .flatMap((provider) => provider.models || [])
  .find((item) => item.id === 'syn/hf:moonshotai/Kimi-K3');

if (!model) throw new Error('Configured Kimi K3 route was not found');
if (!model.input?.includes('image')) {
  model.input = [...new Set([...(model.input || []), 'image'])];
  fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
}
console.log('Pi Kimi K3 image input enabled');
