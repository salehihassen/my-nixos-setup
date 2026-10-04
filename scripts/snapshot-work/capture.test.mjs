import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseSession } from './chromium-session.mjs';
import { captureDesktop, matchBrowserWindow, gallery, saveClipboard, restoreClipboard } from './capture.mjs';

const i32=n=>{const b=Buffer.alloc(4);b.writeInt32LE(n);return b;};
const record=(id,...parts)=>{const data=Buffer.concat(parts),header=Buffer.alloc(3);header.writeUInt16LE(data.length+1);header[2]=id;return Buffer.concat([header,data]);};
const str=(s,wide=false)=>{const data=Buffer.from(s,wide?'utf16le':'utf8');return Buffer.concat([i32(wide?s.length:data.length),data,Buffer.alloc((4-data.length%4)%4)]);};
const nav=(tab,index,url,title)=>{const b=Buffer.concat([i32(tab),i32(index),str(url),str(title,true)]);return record(6,i32(b.length),b);};
const session=(...records)=>Buffer.concat([Buffer.from('SNSS'),i32(3),...records]);

test('SNSS replay handles selected navigation, Unicode, tab movement and closed windows',()=>{
  const result=parseSession(session(
    record(9,i32(100),i32(0)),record(9,i32(200),i32(0)),
    record(0,i32(100),i32(1)),record(2,i32(1),i32(0)),
    nav(1,0,'https://a.example/','Old'),nav(1,1,'https://b.example/','Draft 📝'),
    record(7,i32(1),i32(1)),
    record(0,i32(100),i32(2)),record(2,i32(2),i32(1)),nav(2,0,'https://c.example/','Closed tab'),record(16,i32(2),Buffer.alloc(12)),
    record(0,i32(200),i32(3)),nav(3,0,'https://d.example/','Closed window'),record(17,i32(200),Buffer.alloc(12)),
    record(8,i32(100),i32(0))
  ));
  assert.equal(result.windows.length,1);assert.equal(result.windows[0].tabs.length,1);
  assert.equal(result.windows[0].selectedTab.title,'Draft 📝');
  assert.equal(result.windows[0].selectedTab.url,'https://b.example/');
  assert.deepEqual(result.warnings,[]);
});

test('SNSS truncated writes preserve earlier records and flag the incomplete tail',()=>{
  const complete=session(record(0,i32(100),i32(1)),nav(1,0,'https://a.example/','Draft'));
  const result=parseSession(Buffer.concat([complete,Buffer.from([255,0,6,1])]));
  assert.equal(result.windows[0].tabs[0].title,'Draft');assert.match(result.warnings[0],/Incomplete/);
  const encrypted=Buffer.from(complete);encrypted.writeInt32LE(4,4);
  assert.throws(()=>parseSession(encrypted),/Unsupported/);
});

test('navigation pruning shifts indexes without selecting a deleted history entry',()=>{
  const result=parseSession(session(record(0,i32(1),i32(10)),
    nav(10,0,'https://old/','old'),nav(10,1,'https://keep/','keep'),
    record(7,i32(10),i32(1)),record(11,i32(10),i32(1))));
  assert.equal(result.windows[0].tabs[0].url,'https://keep/');
});

test('browser matching refuses ambiguous titles, including identical tabs in separate windows',()=>{
  const p=[{name:'Default',windows:[{id:1,selectedTab:{title:'Draft'}}]}];
  assert.equal(matchBrowserWindow({title:'Draft - Chromium'},p).id,1);
  p[0].windows.push({id:2,selectedTab:{title:'Draft'}});
  assert.equal(matchBrowserWindow({title:'Draft - Chromium'},p),null);
});

function fixture({failWindow,failProbe=false,interruptAt}={}){
  const windows=[
    {id:4,workspace_id:20,app_id:'editor',is_focused:false,layout:{pos_in_scrolling_layout:[1,1]}},
    {id:2,workspace_id:10,app_id:'terminal',is_focused:true,layout:{pos_in_scrolling_layout:[3,1]}},
    {id:1,workspace_id:10,app_id:'chromium',is_focused:false,layout:{pos_in_scrolling_layout:[1,1]}},
    {id:3,workspace_id:11,app_id:'editor',is_focused:false,layout:{pos_in_scrolling_layout:[1,1]}},
  ];
  const workspaces=[{id:10,idx:1,output:'DP-1',is_active:true,active_window_id:2},{id:11,idx:2,output:'DP-1',is_active:false,active_window_id:3},{id:20,idx:1,output:'eDP-1',is_active:true,active_window_id:4},{id:21,idx:2,output:'eDP-1',active_window_id:null}];
  const calls=[];let checks=0;
  const io={
    query:async name=>({windows,workspaces,outputs:{'DP-1':{},'eDP-1':{}}})[name],
    focus:async(id,restore=false)=>calls.push(['focus',id,restore]),
    workspace:async id=>calls.push(['workspace',id]),
    windowShot:async(id,file)=>{calls.push(['window',id,file]);if((failProbe&&file.endsWith('probe.png'))||(id===failWindow&&!file.endsWith('probe.png')))throw Error('blocked screenshot');},
    outputShot:async(output,file)=>calls.push(['output',output,file]),
    checkpoint:async()=>{},
    checkCancelled:async()=>{if(interruptAt && ++checks>=interruptAt)throw Error('interrupted');}
  };
  const report={captures:[],warnings:[],errors:[]};
  return {calls,io,report};
}

test('captures all columns, workspaces and monitors and restores per-output focus',async()=>{
  const {io,report,calls}=fixture();const browser=[];
  await captureDesktop(io,report,{context:true},async w=>browser.push(w.id));
  assert.deepEqual(calls.filter(c=>c[0]==='focus'&&!c[2]).map(c=>c[1]),[1,2,3,4]);
  assert.equal(report.captures.filter(c=>c.kind==='window'&&c.status==='saved').length,4);
  assert.equal(report.captures.filter(c=>c.kind==='workspace-view').length,5);
  assert.deepEqual(browser,[1]);assert.deepEqual(calls.at(-1),['focus',2,true]);
  assert.ok(calls.some(c=>c[0]==='workspace'&&c[1]===20));
  assert.ok(calls.some(c=>c[0]==='workspace'&&c[1]===21));
});

test('a failed window capture does not prevent others or focus restoration',async()=>{
  const {io,report,calls}=fixture({failWindow:3});
  await captureDesktop(io,report,{context:true});
  assert.equal(report.captures.find(c=>c.kind==='window'&&c.id===3).status,'failed');
  assert.equal(report.captures.find(c=>c.kind==='window'&&c.id===4).status,'saved');
  assert.deepEqual(calls.at(-1),['focus',2,true]);
});

test('lock-screen screenshot refusal aborts before focus changes or browser input',async()=>{
  const {io,report,calls}=fixture({failProbe:true});let inputs=0;
  await assert.rejects(()=>captureDesktop(io,report,{context:true},async()=>inputs++),/blocked/);
  assert.equal(inputs,0);assert.equal(calls.filter(c=>c[0]==='focus').length,0);
});

test('interruption preserves partial captures and still restores focus',async()=>{
  const {io,report,calls}=fixture({interruptAt:3});
  await assert.rejects(()=>captureDesktop(io,report,{context:true}),/interrupted/);
  assert.ok(report.captures.some(c=>c.status==='saved'));
  assert.deepEqual(calls.at(-1),['focus',2,true]);
});

test('gallery escapes untrusted window and tab titles',()=>{
  const html=gallery({startedAt:'now',status:'partial',captures:[{kind:'window',title:'<script>alert(1)</script>',status:'saved',path:'safe.png'}],errors:[],warnings:[]});
  assert.ok(!html.includes('<script>'));assert.ok(html.includes('&lt;script&gt;'));
  assert.ok(html.includes('Content-Security-Policy'));
});

test('an empty clipboard is restored to empty after screenshots',async()=>{
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'capture-clipboard-test-'));
  try{
    const warnings=[];
    const original=await saveClipboard(dir,warnings,async()=>{throw Object.assign(Error('wl-paste failed'),{stderr:'Nothing is copied\n'});});
    assert.deepEqual(original,{empty:true});assert.deepEqual(warnings,[]);
    const calls=[];
    await restoreClipboard(original,async(...args)=>calls.push(args));
    assert.deepEqual(calls,[['wl-copy',['--clear']]]);
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(dir,'original-clipboard.json'),'utf8')),{empty:true});
  }finally{await fs.rm(dir,{recursive:true,force:true});}
});

test('gallery shows saved desktop layout even when no screenshots were captured',()=>{
  const {report}=fixture();report.desktop={windows:[{id:7,title:'Unsaved <draft>',app_id:'editor',workspace_id:10,layout:{pos_in_scrolling_layout:[12,2]}}],workspaces:[{id:10,idx:4,output:'DP-1'}]};
  const html=gallery(report);
  assert.ok(html.includes('Workspace 4'));assert.ok(html.includes('column/row 12/2'));
  assert.ok(html.includes('Unsaved &lt;draft&gt;'));assert.ok(html.includes('No screenshots captured'));
});
