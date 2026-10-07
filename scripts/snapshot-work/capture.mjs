#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { execFile as execFileCallback, spawn } from 'node:child_process';
import { promisify, parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { backupProfiles } from './chromium-session.mjs';

const execFile = promisify(execFileCallback);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const pngMagic = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const browserApp = w => /chromium|google-chrome/i.test(w.app_id || '');
const slug = s => String(s ?? 'unnamed').replace(/[^a-zA-Z0-9._-]+/g, '-').slice(0, 65) || 'unnamed';
const errorText = e => (e.stderr?.toString().trim() || e.message || String(e));
const escape = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const urlLink = s => /^https?:\/\//i.test(s||'') ? `<a href="${escape(s)}" rel="noreferrer">${escape(s)}</a>` : escape(s);
const jsonWrite = (p, v) => fs.writeFile(p, JSON.stringify(v, null, 2) + '\n', {mode:0o600});

export function windowOrder(windows, workspaces) {
  const order = new Map([...workspaces].sort((a,b) => String(a.output).localeCompare(String(b.output)) || a.idx-b.idx).map((w,i)=>[w.id,i]));
  return [...windows].sort((a,b) => (order.get(a.workspace_id)??1e9)-(order.get(b.workspace_id)??1e9)
    || (a.layout?.pos_in_scrolling_layout?.[0]??1e9)-(b.layout?.pos_in_scrolling_layout?.[0]??1e9)
    || (a.layout?.pos_in_scrolling_layout?.[1]??0)-(b.layout?.pos_in_scrolling_layout?.[1]??0) || a.id-b.id);
}

// A unique match is mandatory; never guess which Chromium window receives keys.
export function matchBrowserWindow(window, profiles) {
  const title = String(window.title || '').replace(/ [—–-] (Chromium|Google Chrome)(?: .*)?$/, '');
  const candidates = profiles.flatMap(p => p.windows.map(w => ({profile:p.name,root:p.root,...w})))
    .filter(w => w.selectedTab?.title === title || `${w.selectedTab?.title} - Chromium` === window.title);
  return candidates.length === 1 ? candidates[0] : null;
}

export async function captureDesktop(io, report, options, captureTabs = async()=>{}) {
  const original = { windows: await io.query('windows'), workspaces: await io.query('workspaces'), outputs: await io.query('outputs') };
  report.desktop = original;
  const focused = original.windows.find(w=>w.is_focused);
  let changedFocus = false;
  const folderFor = w => {
    const ws = original.workspaces.find(s=>s.id===w.workspace_id);
    return `screenshots/${slug(ws?.output)}/workspace-${ws?.idx??'unknown'}-id-${w.workspace_id}`;
  };
  try {
    // Screenshots can be silently refused while locked. Require an actual PNG
    // before changing focus or issuing any browser input.
    if (original.windows.length) {
      const probe = focused || original.windows[0];
      await io.windowShot(probe.id, 'screenshots/capture-probe.png');
    }
    for (const w of windowOrder(original.windows, original.workspaces)) {
      const item = {...w, kind:'window', status:'pending'};
      report.captures.push(item);
      try {
        await io.checkCancelled();
        changedFocus = true;
        await io.focus(w.id);
        // Focusing each tiled window scrolls Niri to its column, including
        // columns beyond the right/left edge and windows in tabbed columns.
        const base = `${folderFor(w)}/window-${w.id}-${slug(w.app_id)}`;
        item.path = `${base}.png`;
        await io.windowShot(w.id, item.path);
        item.status = 'saved';
        const ws = original.workspaces.find(s=>s.id===w.workspace_id);
        if (ws?.output && options.context) {
          const context = {kind:'workspace-view', windowId:w.id, workspaceId:ws.id, output:ws.output, title:`Workspace ${ws.idx}, window ${w.id}`, path:`${base}-workspace-view.png`};
          try { await io.outputShot(ws.output, context.path); context.status='saved'; }
          catch(e) { context.status='failed'; context.error=errorText(e); }
          report.captures.push(context);
        }
        if (browserApp(w)) await captureTabs(w, base);
      } catch(e) {
        item.error=errorText(e);
        if(item.status==='saved')report.errors.push(`Window ${w.id}: ${item.error}`);
        else item.status='failed';
      }
      await io.checkpoint();
      await io.checkCancelled();
    }
    // Also record empty workspaces on each connected output.
    for (const ws of original.workspaces.filter(ws=>ws.output && !original.windows.some(w=>w.workspace_id===ws.id))) {
      if (!options.context) continue;
      const item={kind:'workspace-view', workspaceId:ws.id, output:ws.output, title:`Empty workspace ${ws.idx}`,path:`screenshots/${slug(ws.output)}/workspace-${ws.idx}-id-${ws.id}/empty.png`};
      try { await io.checkCancelled(); changedFocus=true; await io.workspace(ws.id); await io.outputShot(ws.output,item.path); item.status='saved'; }
      catch(e) { item.status='failed'; item.error=errorText(e); }
      report.captures.push(item);
    }
  } finally {
    // Restore each workspace's focused window, each monitor's active workspace,
    // then the originally focused window. Exact manual scroll offsets are not
    // exposed by Niri's public action API and cannot be restored precisely.
    for (const ws of original.workspaces.filter(w=>changedFocus && w.active_window_id)) {
      try { await io.focus(ws.active_window_id, true); }
      catch(e) { report.warnings.push(`Restore workspace ${ws.id}: ${errorText(e)}`); }
    }
    for (const ws of original.workspaces.filter(w=>changedFocus && w.is_active && w.output)) {
      try { await io.workspace(ws.id, true); }
      catch(e) { report.warnings.push(`Restore output ${ws.output}: ${errorText(e)}`); }
    }
    if (changedFocus && focused) {
      try { await io.focus(focused.id, true); }
      catch(e) { report.warnings.push(`Restore original focus: ${errorText(e)}`); }
    }
  }
}

export function gallery(report) {
  const cards = report.captures.map(c=>`<article><h3>${escape(c.title || `${c.kind} ${c.id??c.windowId??''}`)}</h3><p>${escape(c.kind)} · ${escape(c.status)}${c.error ? ' · '+escape(c.error):''}</p>${c.status==='saved' && c.path ? `<a href="${escape(c.path)}"><img loading="lazy" src="${escape(c.path)}" alt="${escape(c.title || c.kind)}"></a>`:''}${c.url?`<p>${escape(c.url)}</p>`:''}${c.textPath?`<p><a href="${escape(c.textPath)}">Page text and draft fields</a></p>`:''}</article>`).join('\n');
  const inventories = (report.browserBackup?.profiles||[]).map(p=>`<h3>${escape(p.name)}</h3>`+p.windows.map(w=>`<details><summary>${escape(w.selectedTab?.title||'Browser window')} — ${w.tabs.length} tabs (saved ID ${w.id})</summary><ol>${w.tabs.map(t=>`<li>${escape(t.title)}<br><small>${urlLink(t.url)}</small></li>`).join('')}</ol></details>`).join('')).join('');
  const workspaces = report.desktop ? [...report.desktop.workspaces].sort((a,b)=>String(a.output).localeCompare(String(b.output))||a.idx-b.idx).map(ws=>{
    const windows=windowOrder(report.desktop.windows.filter(w=>w.workspace_id===ws.id),[ws]);
    return `<details open><summary>${escape(ws.output)} · Workspace ${ws.idx} — ${windows.length} windows</summary><ol>${windows.map(w=>`<li><strong>${escape(w.title)}</strong><br><small>${escape(w.app_id)} · column/row ${escape(w.layout?.pos_in_scrolling_layout?.join('/')||'floating')} · window ${w.id}</small></li>`).join('')}</ol></details>`;
  }).join('') : '<p>Desktop inventory was unavailable.</p>';
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' data:; style-src 'unsafe-inline'"><title>Work capture ${escape(report.startedAt)}</title><style>body{font:16px system-ui;margin:2rem;max-width:1500px;background:#15191e;color:#e5e7eb}a{color:#8ac7ff}img{max-width:100%;height:auto}article{border:1px solid #48505b;padding:1rem;break-inside:avoid;margin-bottom:1rem}section{columns:2 420px}pre,small,p{overflow-wrap:anywhere}li{margin:.6rem 0}details{padding:.7rem;border-bottom:1px solid #48505b}summary{cursor:pointer}</style><h1>Work capture</h1><p>${escape(report.startedAt)} · ${escape(report.status)}</p><p>${escape(report.summary || '')}</p><p>Screenshots are visual references, not saved document buffers. Session files can lag live tabs and drafts.</p><ul>${[...report.errors,...report.warnings].map(e=>`<li>${escape(e)}</li>`).join('')}</ul><p><a href="manifest.json">Machine-readable manifest</a> · <a href="browser-inventory.json">Browser inventory</a> · <a href="#desktop">Desktop layout</a> · <a href="#tabs">Browser tabs</a></p><h2>Screenshots</h2><section>${cards||'<p>No screenshots captured.</p>'}</section><h2 id="desktop">Desktop window inventory</h2>${workspaces}<h2 id="tabs">Saved browser session inventory</h2>${inventories}</html>`;
}

// Tab cycling prefers capture-keys, the setgid helper that can only send
// Ctrl+Tab/Ctrl+Shift+Tab (NixOS desktop-control module); elsewhere ydotool.
async function cycleTab(direction) {
  try {
    await run('capture-keys',[direction]);
  } catch(e) {
    if(direction==='tab-next') await run('ydotool',['key','29:1','15:1','15:0','29:0']);
    else await run('ydotool',['key','29:1','42:1','15:1','15:0','42:0','29:0']);
  }
}
async function run(command, args, options={}) {
  const result = await execFile(command,args,{timeout:15000,maxBuffer:32*1024*1024,...options});
  return result.stdout;
}
async function prepareEnvironment() {
  process.env.XDG_RUNTIME_DIR ||= `/run/user/${process.getuid()}`;
  const runtime=process.env.XDG_RUNTIME_DIR;
  if (!process.env.NIRI_SOCKET) {
    const sockets=(await fs.readdir(runtime)).filter(n=>/^niri\..*\.sock$/.test(n));
    if (sockets.length!==1) throw Error(`Found ${sockets.length} Niri sessions. Set NIRI_SOCKET explicitly.`);
    process.env.NIRI_SOCKET=path.join(runtime,sockets[0]);
  }
  process.env.WAYLAND_DISPLAY ||= path.basename(process.env.NIRI_SOCKET).match(/^niri\.(.+)\.\d+\.sock$/)?.[1] || 'wayland-1';
  process.env.DBUS_SESSION_BUS_ADDRESS ||= `unix:path=${runtime}/bus`;
  if (!process.env.YDOTOOL_SOCKET) {
    try { await fs.access('/run/ydotoold/socket'); process.env.YDOTOOL_SOCKET='/run/ydotoold/socket'; } catch {}
  }
}
async function waitPng(file, timeout=7000) {
  const end=Date.now()+timeout;
  while(Date.now()<end) {
    try {
      const data=await fs.readFile(file);
      if (data.length>32 && data.subarray(0,8).equals(pngMagic) && data.subarray(-8,-4).equals(Buffer.from('IEND'))) {
        return {width:data.readUInt32BE(16),height:data.readUInt32BE(20)};
      }
    } catch(e) { if(e.code!=='ENOENT') throw e; }
    await sleep(100);
  }
  throw Error('No complete screenshot was written. The session may be locked or screen capture blocked. No unlock/restart is attempted.');
}
export async function saveClipboard(destination, warnings, execute=run) {
  try {
    const types=(await execute('wl-paste',['--list-types'])).trim().split('\n');
    const mime=types.find(t=>t==='text/plain;charset=utf-8')||types.find(t=>t==='text/plain')||types.find(t=>t==='image/png')||types[0];
    if (!mime) return null;
    const data=await execute('wl-paste',['--no-newline','--type',mime],{encoding:'buffer'});
    await fs.writeFile(path.join(destination,'original-clipboard.bin'),data,{mode:0o600});
    await jsonWrite(path.join(destination,'original-clipboard.json'),{mime,offeredTypes:types});
    return {mime,data};
  } catch(e) {
    if(/nothing is copied/i.test(errorText(e))) {
      await jsonWrite(path.join(destination,'original-clipboard.json'),{empty:true});
      return {empty:true};
    }
    warnings.push('Could not back up clipboard; Niri window screenshots replace its contents. '+errorText(e)); return null;
  }
}
export async function restoreClipboard(saved, execute=run) {
  if(!saved) return;
  if(saved.empty) {await execute('wl-copy',['--clear']);return;}
  await new Promise((resolve,reject)=>{
    // wl-copy forks a clipboard owner. A piped stderr inherited by that daemon
    // would keep Node's event loop alive after the capture has completed.
    const child=spawn('wl-copy',['--type',saved.mime],{stdio:['pipe','ignore','ignore']});
    const timer=setTimeout(()=>{child.kill();reject(Error('Clipboard restore timed out'));},5000);
    child.on('error',e=>{clearTimeout(timer);reject(e);});
    child.on('exit',code=>{clearTimeout(timer);code===0?resolve():reject(Error('Clipboard restore failed'));});
    child.stdin.on('error',()=>{}); child.stdin.end(saved.data);
  });
}

class Cdp {
  constructor(socket) {
    this.socket=socket; this.id=0; this.pending=new Map();
    socket.addEventListener('message',event=>{
      const msg=JSON.parse(event.data); const p=this.pending.get(msg.id); if(!p)return;
      clearTimeout(p.timer); this.pending.delete(msg.id);
      msg.error?p.reject(Error(msg.error.message)):p.resolve(msg.result);
    });
    socket.addEventListener('close',()=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('CDP connection closed'));}this.pending.clear();});
  }
  static async connect(url) {
    const socket=new WebSocket(url);
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{socket.close();reject(Error('CDP connection timed out'));},6000);
      socket.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
      socket.addEventListener('error',()=>{clearTimeout(timer);reject(Error('Cannot connect to browser debugging endpoint'));},{once:true});
    });
    return new Cdp(socket);
  }
  call(method,params={},sessionId) {
    const id=++this.id;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{this.pending.delete(id);reject(Error(`${method} timed out`));},15000);
      this.pending.set(id,{resolve,reject,timer}); this.socket.send(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})}));
    });
  }
}

async function captureCdp(endpoint,destination,report,checkpoint,checkCancelled,tabDelay) {
  const url=new URL(endpoint);
  if(url.protocol!=='http:' || !['127.0.0.1','localhost','[::1]'].includes(url.hostname)) throw Error('--cdp must be a local http:// debugging endpoint');
  const response=await fetch(new URL('/json/version',url),{signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw Error(`CDP discovery HTTP ${response.status}`);
  const version=await response.json();
  const wsUrl=new URL(version.webSocketDebuggerUrl);
  if(!['127.0.0.1','localhost','[::1]'].includes(wsUrl.hostname))throw Error('Refusing a non-local debugger URL');
  const cdp=await Cdp.connect(wsUrl.href);
  try {
    const {targetInfos}=await cdp.call('Target.getTargets');
    report.browserTargets=targetInfos.filter(t=>t.type==='page');
    for(const target of report.browserTargets) {
      checkCancelled();
      const item={kind:'browser-tab',method:'cdp',id:target.targetId,title:target.title,url:target.url,status:'pending'};
      report.captures.push(item); let sessionId;
      try {
        ({sessionId}=await cdp.call('Target.attachToTarget',{targetId:target.targetId,flatten:true}));
        const base=`browser-tabs/cdp-${slug(target.targetId)}`;
        await fs.mkdir(path.join(destination,'browser-tabs'),{recursive:true,mode:0o700});
        // Do not navigate, reload, resize, or bring the page to the foreground.
        await sleep(tabDelay);checkCancelled();
        const shot=await cdp.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false,fromSurface:true},sessionId);
        item.path=`${base}.png`;
        await fs.writeFile(path.join(destination,item.path),Buffer.from(shot.data,'base64'),{mode:0o600});
        await waitPng(path.join(destination,item.path)); item.status='saved';
        try {
          const {result,exceptionDetails}=await cdp.call('Runtime.evaluate',{returnByValue:true,expression:`JSON.stringify({url:location.href,title:document.title,text:document.body?.innerText||'',fields:[...document.querySelectorAll('textarea,input,[contenteditable="true"]')].filter(e=>!['password','hidden','file'].includes(e.type)).map(e=>({tag:e.tagName,id:e.id,name:e.name,type:e.type,value:e.value??e.innerText}))})`},sessionId);
          if(exceptionDetails)throw Error('Page text evaluation failed');
          const data=JSON.parse(result.value);
          item.textPath=`${base}-text.json`; await jsonWrite(path.join(destination,item.textPath),data);
        } catch(e) { item.textError=errorText(e);report.warnings.push(`Tab ${target.targetId}: draft text unavailable`); }
      } catch(e) {item.status='failed';item.error=errorText(e);}
      finally {if(sessionId)await cdp.call('Target.detachFromTarget',{sessionId}).catch(()=>{});}
      await checkpoint();
    }
    const after=(await cdp.call('Target.getTargets')).targetInfos.filter(t=>t.type==='page').map(t=>t.targetId).sort();
    if(JSON.stringify(after)!==JSON.stringify(report.browserTargets.map(t=>t.targetId).sort()))report.warnings.push('Browser tabs changed during capture; rerun to include new tabs.');
  } finally {cdp.socket.close();}
}

export async function main(argv=process.argv.slice(2)) {
  const {values}=parseArgs({args:argv,options:{help:{type:'boolean',short:'h'},output:{type:'string',short:'o'},'backup-only':{type:'boolean'},'no-tabs':{type:'boolean'},'no-context':{type:'boolean'},'browser-root':{type:'string',multiple:true},'tab-count':{type:'string',multiple:true},cdp:{type:'string'},delay:{type:'string',default:'800'},'tab-delay':{type:'string',default:'5000'}}});
  if(values.help){console.log(`Usage: capture-work [options]
  -o, --output DIR       Override ~/Pictures/snapshot-work/START-TIME/
  --backup-only          Copy saved Chromium sessions and produce tab inventory
  --browser-root DIR     Chromium user-data root (repeat for multiple browsers)
  --cdp http://127.0.0.1:PORT  Capture tabs and draft text via an ALREADY enabled debugger
  --tab-count ID:COUNT   Explicit tab count for a Niri browser window (repeatable)
  --no-tabs              Window/workspace screenshots only
  --no-context           Skip workspace viewport screenshots
  --delay MILLISECONDS   Settle time after desktop focus changes (default 800)
  --tab-delay MILLISECONDS  Wait before every browser tab screenshot (default 5000)

By default, tabs are captured with Ctrl+Tab using a uniquely matched saved
Chromium session window as the count. This is best effort: session state may
lag, titles may repeat, and discarded tabs may reload when selected. No browser
is started/restarted. Ambiguous windows are reported and skipped. Use --cdp
when already available for exact target enumeration and draft text capture.

Run from your normal terminal/SSH as the desktop user; no sudo. The desktop
must permit screenshots and focus changes. Stop with Ctrl+C. Never reboots,
closes a window, saves a document, or unlocks the desktop. See README.md.`);return 0;}
  const delay=Number(values.delay);
  if(!Number.isFinite(delay)||delay<100||delay>30000)throw Error('--delay must be between 100 and 30000 ms');
  const tabDelay=Number(values['tab-delay']);
  if(!Number.isFinite(tabDelay)||tabDelay<5000||tabDelay>60000)throw Error('--tab-delay must be between 5000 and 60000 ms');
  const counts=new Map();
  for(const entry of values['tab-count']||[]){const m=/^(\d+):(\d+)$/.exec(entry);if(!m||+m[2]<1||+m[2]>2000)throw Error('--tab-count requires ID:COUNT, count 1–2000');counts.set(+m[1],+m[2]);}
  process.umask(0o077);
  const startedAt=new Date().toISOString();
  const destination=path.resolve(values.output||path.join(os.homedir(),'Pictures','snapshot-work',startedAt.replaceAll(':','-')));
  await fs.mkdir(path.dirname(destination),{recursive:true,mode:0o700});
  await fs.mkdir(destination,{mode:0o700}); // Refuse to overwrite any previous capture.
  const report={version:1,startedAt,status:'running',settings:{focusDelayMs:delay,tabDelayMs:tabDelay},captures:[],errors:[],warnings:[]};
  const checkpoint=async()=>{await jsonWrite(path.join(destination,'manifest.json'),report);await fs.writeFile(path.join(destination,'index.html'),gallery(report));};
  let cancelled=false, clipboard;
  const onSignal=()=>{cancelled=true;};process.on('SIGINT',onSignal);process.on('SIGTERM',onSignal);
  const checkCancelled=()=>{if(cancelled)throw Error('Capture interrupted; partial results retained');};
  console.log(`Saving to ${destination}`);
  try {
    const roots=values['browser-root']||['chromium','google-chrome','google-chrome-beta'].map(n=>path.join(os.homedir(),'.config',n));
    report.browserBackup=await backupProfiles(roots,destination);
    await jsonWrite(path.join(destination,'browser-inventory.json'),report.browserBackup);
    report.warnings.push(...report.browserBackup.warnings,...report.browserBackup.profiles.flatMap(p=>p.warnings.map(w=>`${p.name}: ${w}`)));
    await checkpoint();
    if(!values['backup-only']) {
      if(values.cdp && !values['no-tabs']) {
        try {await captureCdp(values.cdp,destination,report,checkpoint,checkCancelled,tabDelay);}
        catch(e){report.errors.push(`Browser capture: ${errorText(e)}`);}
      }
      try {
        await prepareEnvironment();
        const query=async name=>JSON.parse(await run('niri',['msg','--json',name]));
        const action=(name,...args)=>run('niri',['msg','action',name,...args.map(String)]);
        await query('windows'); // Fail early if the caller is sandboxed.
        clipboard=await saveClipboard(destination,report.warnings);
        const ensureParent=relative=>fs.mkdir(path.dirname(path.join(destination,relative)),{recursive:true,mode:0o700});
        const io={query,checkpoint,checkCancelled,
          focus:async(id,restoring=false)=>{
            if(!restoring)checkCancelled();
            await action('focus-window','--id',id);await sleep(delay);
            const current=await query('focused-window');
            if(current?.id!==id)throw Error(`Could not focus window ${id}; desktop may be locked`);
          },
          workspace:async id=>{
            const ws=(await query('workspaces')).find(w=>w.id===id);
            if(!ws?.output)throw Error(`Workspace ${id} no longer has an output`);
            await action('focus-monitor',ws.output);
            await action('focus-workspace',String(ws.idx));await sleep(delay);
          },
          windowShot:async(id,relative)=>{await ensureParent(relative);await action('screenshot-window','--id',id,'--path',path.join(destination,relative));return waitPng(path.join(destination,relative));},
          outputShot:async(output,relative)=>{await ensureParent(relative);await run('grim',['-o',output,path.join(destination,relative)]);return waitPng(path.join(destination,relative));},
        };
        const keyboardTabs=async(w,base)=>{
          if(values['no-tabs']||values.cdp)return;
          const match=matchBrowserWindow(w,report.browserBackup.profiles);
          const count=counts.get(w.id)||match?.tabs.length;
          if(!count){report.errors.push(`Browser window ${w.id}: cannot uniquely match saved tabs; use --tab-count ${w.id}:COUNT or an existing --cdp endpoint.`);return;}
          report.warnings.push(`Browser window ${w.id}: ${count} tabs requested by ${counts.has(w.id)?'explicit count':'saved-session estimate'}; keyboard capture does not verify complete live tab coverage.`);
          let advances=0;
          const next=async()=>{
            const current=await query('focused-window');
            if(current?.id!==w.id)throw Error(`Focus moved away from browser ${w.id}; refusing keyboard input`);
            await cycleTab('tab-next');
            advances++;
          };
          try {
            for(let i=0;i<count;i++) {
              checkCancelled();
              await sleep(tabDelay);checkCancelled();
              const current=await query('focused-window');
              if(current?.id!==w.id)throw Error(`Focus changed during browser capture ${w.id}`);
              const item={kind:'browser-tab',method:'keyboard',windowId:w.id,sequence:i+1,title:current.title,path:`${base}-tab-${String(i+1).padStart(3,'0')}.png`,status:'pending'};
              report.captures.push(item);
              try{await io.windowShot(w.id,item.path);item.status='saved';item.capturedAt=new Date().toISOString();}
              catch(e){item.status='failed';item.error=errorText(e);throw e;}
              await checkpoint();
              console.log(`Browser ${w.id}: tab ${i+1}/${count}`);
              if(i+1<count)await next();
            }
          } catch(e) {
            report.errors.push(`Browser window ${w.id}: ${errorText(e)}`);
          } finally {
            // Reverse exactly the advances we issued, so restoration does not
            // depend on the potentially stale saved tab count.
            if(advances>0){
              const current=await query('focused-window');
              if(current?.id===w.id){
                for(let i=0;i<advances;i++){
                  if((await query('focused-window'))?.id!==w.id){report.warnings.push(`Browser ${w.id}: tab restoration stopped because focus changed`);break;}
                  await cycleTab('tab-prev');await sleep(90);
                }
                await sleep(delay);
              }else report.warnings.push(`Browser ${w.id}: original tab not restored because focus changed`);
            }
          }
        };
        await captureDesktop(io,report,{context:!values['no-context']},keyboardTabs);
        if(values['no-tabs'] && report.desktop.windows.some(browserApp))report.warnings.push('Browser tab capture explicitly disabled. Only active tabs appear in window screenshots.');
      }catch(e){report.errors.push(`Desktop capture: ${errorText(e)}`);}
    }
  }catch(e){report.errors.push(errorText(e));}
  finally {
    try{await restoreClipboard(clipboard);}catch(e){report.warnings.push(errorText(e));}
    process.removeListener('SIGINT',onSignal);process.removeListener('SIGTERM',onSignal);
    report.finishedAt=new Date().toISOString();
    const saved=report.captures.filter(c=>c.status==='saved').length;
    const failed=report.captures.filter(c=>c.status!=='saved').length;
    const savedTabs=report.browserBackup?.profiles.reduce((n,p)=>n+p.windows.reduce((m,w)=>m+w.tabs.length,0),0)||0;
    report.status=values['backup-only']?'session-backup-only':report.errors.length||failed?'partial':report.warnings.length?'review-required':'captured';
    report.summary=`${saved} screenshots saved; ${failed} capture failures; ${savedTabs} tabs in saved session inventory. ${report.errors.length} errors.`;
    await checkpoint();
    console.log(`${report.summary}\nReport: ${path.join(destination,'index.html')}`);
    for(const e of report.errors)console.error(e);
  }
  return report.errors.length||report.captures.some(c=>c.status==='failed')?2:0;
}

if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().then(code=>{process.exitCode=code;}).catch(e=>{console.error(errorText(e));process.exitCode=1;});
