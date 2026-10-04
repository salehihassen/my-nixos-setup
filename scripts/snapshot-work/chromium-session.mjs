// Reads Chromium's little-endian SNSS session command stream, without opening
// or changing the live profile. This is a best-effort inventory, not a restore tool.
// Format references are linked in README.md.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';

export function parseSession(bytes) {
  if (bytes.length < 8 || bytes.toString('ascii', 0, 4) !== 'SNSS') throw Error('Not an SNSS session');
  const version = bytes.readInt32LE(4);
  if (![1, 3].includes(version)) throw Error(`Unsupported/encrypted SNSS version ${version}; raw backup retained`);
  const tabs = new Map(), windows = new Map(), closed = new Set(), warnings = [];
  const tab = id => {
    if (!tabs.has(id)) tabs.set(id, { id, windowId: null, index: -1, navigationIndex: 0, navigations: new Map() });
    return tabs.get(id);
  };
  const win = id => {
    if (!windows.has(id)) windows.set(id, { id, selectedIndex: 0, tabs: [] });
    return windows.get(id);
  };
  let offset = 8, commands = 0;
  while (offset + 2 <= bytes.length) {
    const length = bytes.readUInt16LE(offset);
    if (length < 1 || offset + length + 2 > bytes.length) { warnings.push('Incomplete trailing record'); break; }
    const id = bytes[offset + 2], data = bytes.subarray(offset + 3, offset + 2 + length);
    const int = at => data.readInt32LE(at);
    try {
      if (id === 0) tab(int(4)).windowId = int(0);
      else if (id === 2) tab(int(0)).index = int(4);
      else if (id === 7) tab(int(0)).navigationIndex = int(4);
      else if (id === 8) win(int(0)).selectedIndex = int(4);
      else if (id === 9) { win(int(0)).type = int(4); closed.delete(int(0)); }
      else if (id === 12) tab(int(0)).pinned = !!data[4];
      else if (id === 16) tabs.delete(int(0));
      else if (id === 17) { windows.delete(int(0)); closed.add(int(0)); }
      else if ([5, 11, 24].includes(id)) {
        const t = tab(int(0));
        const start = id === 11 ? 0 : int(4);
        const count = id === 5 ? Infinity : id === 11 ? int(4) : int(8);
        t.navigations = new Map([...t.navigations].flatMap(([i, n]) => {
          if (i >= start && i < start + count) return [];
          const next = i >= start + count ? i - count : i;
          return [[next, { ...n, index: next }]];
        }));
        if (id !== 5) {
          if (t.navigationIndex >= start + count) t.navigationIndex -= count;
          else if (t.navigationIndex >= start) t.navigationIndex = start - 1;
        }
      } else if (id === 6) {
        // A Pickle header precedes tab id, navigation index, URL and UTF-16 title.
        let cursor = 4;
        const readInt = () => { const value = int(cursor); cursor += 4; return value; };
        const readString = wide => {
          const count = readInt(), size = count * (wide ? 2 : 1);
          if (count < 0 || cursor + size > data.length) throw Error('Invalid string length');
          const value = data.toString(wide ? 'utf16le' : 'utf8', cursor, cursor + size);
          cursor += Math.ceil(size / 4) * 4;
          return value;
        };
        const tabId = readInt(), index = readInt();
        tab(tabId).navigations.set(index, { index, url: readString(false), title: readString(true) });
      }
    } catch (error) { warnings.push(`Record ${commands}, command ${id}: ${error.message}`); }
    commands++; offset += length + 2;
  }
  if (offset !== bytes.length && !warnings.includes('Incomplete trailing record')) warnings.push('Trailing bytes ignored');
  for (const t of tabs.values()) {
    if (t.windowId === null || closed.has(t.windowId) || !t.navigations.size) continue;
    const navs = [...t.navigations.values()].sort((a, b) => a.index - b.index);
    const current = navs.find(n => n.index >= t.navigationIndex) || navs.at(-1);
    win(t.windowId).tabs.push({ id: t.id, index: t.index, pinned: !!t.pinned, ...current });
    // Keep visual tab index separate from navigation history index.
    win(t.windowId).tabs.at(-1).index = t.index;
  }
  const result = [...windows.values()].filter(w => w.tabs.length && !closed.has(w.id));
  for (const w of result) {
    w.tabs.sort((a, b) => a.index - b.index || a.id - b.id);
    w.selectedTab = w.tabs.find(t => t.index === w.selectedIndex) || w.tabs[0];
  }
  return { version, commands, warnings, windows: result };
}

export async function backupProfiles(roots, destination) {
  const profiles = [], files = [], warnings = [];
  for (let rootIndex = 0; rootIndex < roots.length; rootIndex++) {
    const root = roots[rootIndex];
    let entries;
    try { entries = await fs.readdir(root, { withFileTypes: true }); }
    catch (e) { if (e.code !== 'ENOENT') warnings.push(`${root}: ${e.message}`); continue; }
    for (const entry of entries.filter(e => e.isDirectory() && /^(Default|Profile \d+)$/.test(e.name))) {
      const sessions = path.join(root, entry.name, 'Sessions');
      let names;
      try { names = (await fs.readdir(sessions)).filter(n => /^(Session|Tabs)_\d+$/.test(n)).sort(); }
      catch (e) { if (e.code !== 'ENOENT') warnings.push(`${sessions}: ${e.message}`); continue; }
      const profile = { root, name: entry.name, windows: [], warnings: [], latestSession: null };
      const copied = [];
      for (const name of names) {
        try {
          const source = path.join(sessions, name);
          const relative = path.join('browser-sessions', `browser-${rootIndex + 1}`, entry.name, 'Sessions', name);
          const target = path.join(destination, relative);
          // A browser can append during a read. Snapshot bytes, preserve their hash,
          // and explicitly mark this as a live (non-atomic) backup.
          const data = await fs.readFile(source), stat = await fs.stat(source);
          await fs.mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
          await fs.writeFile(target, data, { flag: 'wx', mode: 0o600 });
          files.push({ source, path: relative, bytes: data.length, mtime: stat.mtime.toISOString(), sha256: createHash('sha256').update(data).digest('hex') });
          if (name.startsWith('Session_')) copied.push({ name, data, mtime: stat.mtime.toISOString() });
        } catch (e) { profile.warnings.push(`${name}: ${e.message}`); }
      }
      const latest = copied.at(-1);
      if (latest) {
        profile.latestSession = latest.name; profile.savedAt = latest.mtime;
        try { const parsed = parseSession(latest.data); profile.windows = parsed.windows; profile.warnings.push(...parsed.warnings); }
        catch (e) { profile.warnings.push(e.message); }
      }
      profiles.push(profile);
    }
  }
  return { profiles, files, warnings, consistency: 'Live file copies; may lag in-memory tabs and drafts. Raw files retained. Incognito and unsaved app buffers are not backed up.' };
}
