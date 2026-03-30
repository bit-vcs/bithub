///|
fn render_home_page() -> String {
  let home_css =
    #|.landing{max-width:600px;margin:40px auto;}
    #|.landing h1{font-size:28px;margin-bottom:4px;}
    #|.landing p{color:#8b949e;margin-bottom:20px;}
    #|.section{background:var(--pre);padding:20px;border-radius:8px;border:1px solid var(--border);margin-bottom:16px;}
    #|.section h2{font-size:16px;margin:0 0 12px;}
    #|.section label{font-size:13px;color:#8b949e;display:block;margin-bottom:4px;}
    #|.section input{padding:8px 12px;border:1px solid var(--border);border-radius:6px;background:var(--bg);color:var(--text);font-size:14px;font-family:inherit;width:100%;box-sizing:border-box;margin-bottom:8px;}
    #|.btn{padding:10px 16px;background:#238636;color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer;font-weight:600;width:100%;}
    #|.btn:hover{background:#2ea043;}.btn:disabled{opacity:0.5;cursor:not-allowed;}
    #|.btn-secondary{background:var(--panel);color:var(--text);border:1px solid var(--border);}
    #|.btn-secondary:hover{background:var(--pre);}
    #|.identity-info{font-size:12px;color:#8b949e;margin-top:8px;word-break:break-all;}
    #|.identity-info code{background:var(--pre);padding:2px 4px;border-radius:3px;}
    #|.btn-row{display:flex;gap:8px;margin-top:8px;}
    #|.btn-row .btn{flex:1;}
    #|.ws-progress{display:none;margin-top:12px;}.ws-progress-track{height:6px;background:var(--border);border-radius:3px;overflow:hidden;}
    #|.ws-progress-bar{height:100%;background:#238636;border-radius:3px;transition:width 0.3s ease;}
    #|.ws-progress-text{font-size:12px;color:#8b949e;margin-top:4px;min-height:16px;}
    #|.ws-recent{margin-top:16px;}.ws-recent h3{font-size:14px;color:#8b949e;margin-bottom:8px;}
    #|.ws-recent a{display:block;padding:6px 0;color:var(--link);text-decoration:none;}.ws-recent a:hover{text-decoration:underline;}
  let home_js =
    #|<script>
    #|// --- Identity (Ed25519 key pair in IndexedDB) ---
    #|const ID_DB='bithub-identity',ID_VER=1,ID_STORE='keys';
    #|function openIdDB(){return new Promise((ok,ng)=>{const r=indexedDB.open(ID_DB,ID_VER);r.onupgradeneeded=()=>r.result.createObjectStore(ID_STORE);r.onsuccess=()=>ok(r.result);r.onerror=()=>ng(r.error);});}
    #|async function idGet(k){const db=await openIdDB();return new Promise(ok=>{const r=db.transaction(ID_STORE).objectStore(ID_STORE).get(k);r.onsuccess=()=>ok(r.result??null);r.onerror=()=>ok(null);});}
    #|async function idPut(k,v){const db=await openIdDB();return new Promise(ok=>{const tx=db.transaction(ID_STORE,'readwrite');tx.objectStore(ID_STORE).put(v,k);tx.oncomplete=()=>ok();});}
    #|
    #|async function generateIdentity(){
    #|  const kp=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
    #|  const pubJwk=await crypto.subtle.exportKey('jwk',kp.publicKey);
    #|  const privJwk=await crypto.subtle.exportKey('jwk',kp.privateKey);
    #|  const raw=await crypto.subtle.exportKey('raw',kp.publicKey);
    #|  const fp=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',raw))).map(b=>b.toString(16).padStart(2,'0')).join('').slice(0,16);
    #|  return{publicKey:pubJwk,privateKey:privJwk,fingerprint:fp};
    #|}
    #|
    #|async function loadOrCreateIdentity(){
    #|  let id=await idGet('identity');
    #|  if(!id){
    #|    id=await generateIdentity();
    #|    id.displayName='';
    #|    id.createdAt=Date.now();
    #|    await idPut('identity',id);
    #|  }
    #|  return id;
    #|}
    #|
    #|async function exportIdentity(){
    #|  const id=await idGet('identity');
    #|  if(!id)return alert('No identity');
    #|  const blob=new Blob([JSON.stringify(id,null,2)],{type:'application/json'});
    #|  if(window.showSaveFilePicker){
    #|    try{const fh=await window.showSaveFilePicker({suggestedName:'bithub-identity.json',types:[{description:'Identity',accept:{'application/json':['.json']}}]});
    #|    const ws=await fh.createWritable();await ws.write(blob);await ws.close();return;}catch{}
    #|  }
    #|  const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='bithub-identity.json';a.click();
    #|}
    #|
    #|async function importIdentity(){
    #|  if(window.showOpenFilePicker){
    #|    try{const[fh]=await window.showOpenFilePicker({types:[{accept:{'application/json':['.json']}}]});
    #|    const f=await fh.getFile();const id=JSON.parse(await f.text());
    #|    if(!id.fingerprint||!id.privateKey)return alert('Invalid identity file');
    #|    await idPut('identity',id);location.reload();return;}catch{}
    #|  }
    #|  const input=document.createElement('input');input.type='file';input.accept='.json';
    #|  input.onchange=async()=>{const f=input.files[0];if(!f)return;const id=JSON.parse(await f.text());
    #|  if(!id.fingerprint||!id.privateKey)return alert('Invalid');await idPut('identity',id);location.reload();};input.click();
    #|}
    #|
    #|// --- Blob DB (for commit metadata) ---
    #|const BLOB_DB='bithub-blobs',BLOB_VER=1,BLOB_STORE='blobs';
    #|let _blobDbP=null;
    #|function openBlobDB(){if(_blobDbP)return _blobDbP;_blobDbP=new Promise((ok,ng)=>{const r=indexedDB.open(BLOB_DB,BLOB_VER);r.onupgradeneeded=()=>r.result.createObjectStore(BLOB_STORE);r.onsuccess=()=>ok(r.result);r.onerror=()=>{_blobDbP=null;ng(r.error);};});return _blobDbP;}
    #|async function idbPut(k,v){const db=await openBlobDB();return new Promise(ok=>{const tx=db.transaction(BLOB_STORE,'readwrite');tx.objectStore(BLOB_STORE).put(v,k);tx.oncomplete=()=>ok();});}
    #|async function idbPutBatch(entries){const db=await openBlobDB();return new Promise((ok,ng)=>{const tx=db.transaction(BLOB_STORE,'readwrite');const s=tx.objectStore(BLOB_STORE);for(const[k,v]of entries)s.put(v,k);tx.oncomplete=()=>ok();tx.onerror=()=>ng(tx.error);});}
    #|
    #|// --- Workspace ---
    #|const WS_KEY='bithub_workspaces';
    #|function getWorkspaces(){try{return JSON.parse(localStorage.getItem(WS_KEY)||'[]');}catch{return [];}}
    #|function saveWorkspace(ws){const all=getWorkspaces().filter(w=>w.id!==ws.id);all.unshift(ws);localStorage.setItem(WS_KEY,JSON.stringify(all.slice(0,10)));}
    #|
    #|async function updateDisplayName(){
    #|  const name=document.getElementById('id-name').value.trim();
    #|  const id=await idGet('identity');if(!id)return;
    #|  id.displayName=name;await idPut('identity',id);
    #|  document.getElementById('id-status').textContent='Saved';setTimeout(()=>document.getElementById('id-status').textContent='',1500);
    #|}
    #|
    #|function showProgress(msg,pct){
    #|  const el=document.getElementById('ws-progress');
    #|  const bar=document.getElementById('ws-bar');
    #|  const txt=document.getElementById('ws-progress-text');
    #|  el.style.display='block';bar.style.width=pct+'%';txt.textContent=msg;
    #|}
    #|function hideProgress(){document.getElementById('ws-progress').style.display='none';}
    #|
    #|async function openWorkspace(e){
    #|  e.preventDefault();
    #|  const repo=document.getElementById('ws-repo').value.trim();
    #|  if(!repo||!repo.includes('/'))return alert('Enter owner/repo');
    #|  const btn=document.getElementById('ws-btn');btn.disabled=true;btn.textContent='Cloning...';
    #|  showProgress('Connecting to GitHub...',10);
    #|  const id=await loadOrCreateIdentity();
    #|  const wsId=repo.replace(/\//g,'-')+'-'+Date.now().toString(36);
    #|  try{
    #|    showProgress('Fetching repository metadata...',20);
    #|    const r=await(await fetch('/api/init?repo='+repo,{method:'POST'})).json();
    #|    if(!r.ok){showProgress('Error: '+(r.error||'?'),100);btn.textContent='Retry';btn.disabled=false;return;}
    #|    showProgress('Server loaded '+r.files+' files. Caching locally...',60);
    #|    // Cache to IndexedDB (batch writes, parallel fetches)
    #|    const gh='https://api.github.com/repos/'+repo;
    #|    const ghH={Accept:'application/vnd.github.v3+json'};
    #|    let cached=0;
    #|    try{
    #|      const tr=await(await fetch(gh+'/git/trees/'+(r.default_branch||'main')+'?recursive=1',{headers:ghH})).json();
    #|      const blobs=(tr.tree||[]).filter(e=>e.type==='blob'&&e.size<50000).slice(0,200);
    #|      const CHUNK=10;
    #|      for(let c=0;c<blobs.length;c+=CHUNK){
    #|        const chunk=blobs.slice(c,c+CHUNK);
    #|        showProgress('Caching files ('+(c+1)+'-'+Math.min(c+CHUNK,blobs.length)+'/'+blobs.length+')',60+Math.round(35*c/blobs.length));
    #|        const results=await Promise.allSettled(chunk.map(async e=>{
    #|          const b=await(await fetch(gh+'/git/blobs/'+e.sha,{headers:ghH})).json();
    #|          if(b.encoding==='base64'){const bin=Uint8Array.from(atob(b.content.replace(/\n/g,'')),c=>c.charCodeAt(0));return[e.path,new TextDecoder().decode(bin)];}
    #|          return null;
    #|        }));
    #|        const batch=results.filter(r=>r.status==='fulfilled'&&r.value).map(r=>r.value);
    #|        if(batch.length>0){await idbPutBatch(batch.map(([p,v])=>['ws:'+wsId+':file:'+p,v]));cached+=batch.length;}
    #|      }
    #|    }catch{}
    #|    // Store HEAD commit metadata in IDB
    #|    try{
    #|      const commitRes=await fetch(gh+'/commits?sha='+(r.default_branch||'main')+'&per_page=1',{headers:ghH});
    #|      const commits=await commitRes.json();
    #|      if(commits.length>0){const c=commits[0];await idbPut('ws:'+wsId+':commit:'+c.sha,JSON.stringify({sha:c.sha,message:c.commit.message,author:c.commit.author.name,date:c.commit.author.date}));await idbPut('ws:'+wsId+':HEAD',c.sha);}
    #|    }catch{}
    #|    showProgress('Done! '+r.files+' files ('+cached+' cached locally)',100);
    #|    saveWorkspace({id:wsId,repo,user:id.displayName||id.fingerprint,fingerprint:id.fingerprint,created:Date.now(),files:r.files});
    #|    setTimeout(()=>{window.location.href='/workspace/'+wsId+'/filer';},500);
    #|  }catch{showProgress('Failed',100);btn.textContent='Retry';btn.disabled=false;}
    #|}
    #|
    #|// --- Init UI ---
    #|async function initPage(){
    #|  const id=await loadOrCreateIdentity();
    #|  document.getElementById('id-name').value=id.displayName||'';
    #|  document.getElementById('id-fp').textContent=id.fingerprint;
    #|  // Recent workspaces
    #|  const el=document.getElementById('ws-recent-list');
    #|  getWorkspaces().forEach(w=>{const a=document.createElement('a');a.href='/workspace/'+w.id+'/filer';a.textContent=w.repo+' — '+(w.user||w.fingerprint);el.appendChild(a);});
    #|}
    #|document.addEventListener('DOMContentLoaded',initPage);
    #|</script>
  render_layout("bithub", [
    @luna.raw_html("<style>" + home_css + "</style>"),
    @luna.raw_html({
      let html =
        #|<div class="landing">
        #|<h1>bithub</h1>
        #|<p>Browse and collaborate on any GitHub repository.</p>
        #|
        #|<div class="section">
        #|  <h2>Identity</h2>
        #|  <label>Display Name</label>
        #|  <input id="id-name" placeholder="anonymous" onchange="updateDisplayName()" />
        #|  <div class="identity-info">Fingerprint: <code id="id-fp">loading...</code> <span id="id-status"></span></div>
        #|  <div class="btn-row">
        #|    <button class="btn btn-secondary" onclick="exportIdentity()">Export key</button>
        #|    <button class="btn btn-secondary" onclick="importIdentity()">Import key</button>
        #|  </div>
        #|  <div style="margin-top:12px;padding-top:12px;border-top:1px solid var(--border);">
        #|    <label>Storage</label>
        #|    <div class="identity-info">Mode: <code id="storage-mode">indexeddb</code></div>
        #|    <button class="btn btn-secondary" style="margin-top:8px;" onclick="connectFS()">Connect File System</button>
        #|  </div>
        #|</div>
        #|
        #|<form class="section" onsubmit="openWorkspace(event)">
        #|  <h2>Open Repository</h2>
        #|  <label>Repository (owner/repo)</label>
        #|  <input id="ws-repo" placeholder="e.g. bit-vcs/bit-relay" required />
        #|  <button id="ws-btn" class="btn" type="submit">Clone &amp; Open</button>
        #|  <div id="ws-progress" class="ws-progress"><div class="ws-progress-track"><div id="ws-bar" class="ws-progress-bar" style="width:0%"></div></div><div id="ws-progress-text" class="ws-progress-text"></div></div>
        #|</form>
        #|
        #|<div class="ws-recent"><h3>Recent workspaces</h3><div id="ws-recent-list"></div></div>
        #|</div>
      html
    }),
  ]) + home_js
}


///|
fn render_workspace_spa(ws : String) -> String {
  let prefix = "/workspace/" + ws
  let spa_js =
    #|<script>
    #|// --- IndexedDB helpers ---
    #|const DB_NAME='bithub-blobs',DB_VER=1,STORE='blobs';
    #|let _dbP=null;
    #|function openDB(){if(_dbP)return _dbP;_dbP=new Promise((ok,ng)=>{const r=indexedDB.open(DB_NAME,DB_VER);r.onupgradeneeded=()=>r.result.createObjectStore(STORE);r.onsuccess=()=>ok(r.result);r.onerror=()=>{_dbP=null;ng(r.error);};});return _dbP;}
    #|async function idbGet(k){const db=await openDB();return new Promise(ok=>{const r=db.transaction(STORE).objectStore(STORE).get(k);r.onsuccess=()=>ok(r.result??null);r.onerror=()=>ok(null);});}
    #|async function idbPut(k,v){const db=await openDB();return new Promise((ok,ng)=>{const tx=db.transaction(STORE,'readwrite');const s=tx.objectStore(STORE);s.put(v,k);tx.oncomplete=()=>ok();tx.onerror=()=>ng(tx.error);});}
    #|async function idbKeys(pfx){const db=await openDB();return new Promise(ok=>{const r=db.transaction(STORE).objectStore(STORE).getAllKeys();r.onsuccess=()=>ok((r.result||[]).filter(k=>typeof k==='string'&&k.startsWith(pfx)));r.onerror=()=>ok([]);});}
    #|function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
    #|
    #|// --- SPA Router ---
    #|const WS_PREFIX=document.body.dataset.wsPrefix;
    #|const WS_ID=document.body.dataset.wsId;
    #|const KEY_PFX='ws:'+WS_ID+':file:';
    #|
    #|function subPath(){
    #|  const full=location.pathname;
    #|  const base=WS_PREFIX+'/';
    #|  return full.startsWith(base)?full.slice(base.length):(full===WS_PREFIX?'':full.slice(WS_PREFIX.length+1));
    #|}
    #|
    #|// Known SPA routes
    #|const ROUTES=['commits','branches','issues','pulls','activity','actions','readme','search','filer','file','stats','tags','webhooks'];
    #|
    #|async function navigate(path,push){
    #|  if(push)history.pushState(null,'',WS_PREFIX+'/'+(path||''));
    #|  const title=document.getElementById('spa-title');
    #|  const content=document.getElementById('spa-content');
    #|  const route=path.split('/')[0]||'';
    #|  if(ROUTES.includes(route)){
    #|    if(route==='commits')return renderCommits(title,content);
    #|    // Other known routes: show placeholder
    #|    title.textContent=route;
    #|    content.innerHTML='<p>'+esc(route)+' view — coming soon for local workspace</p>';
    #|    return;
    #|  }
    #|  // File/directory browse
    #|  return renderBrowse(path,title,content);
    #|}
    #|
    #|// --- Browse (file/dir auto-detect) ---
    #|async function renderBrowse(path,title,content){
    #|  const fileContent=await idbGet(KEY_PFX+path);
    #|  if(fileContent!==null)return renderFile(path,fileContent,title,content);
    #|  // Directory
    #|  const allKeys=await idbKeys(KEY_PFX);
    #|  const seen=new Set();const entries=[];
    #|  for(const k of allKeys){
    #|    const rel=k.slice(KEY_PFX.length);
    #|    if(path&&!rel.startsWith(path+'/'))continue;
    #|    const sub=path?rel.slice(path.length+1):rel;
    #|    if(!sub)continue;
    #|    const slash=sub.indexOf('/');
    #|    if(slash<0)entries.push({name:sub,full:rel,dir:false});
    #|    else{const d=sub.slice(0,slash),dp=path?path+'/'+d:d;if(!seen.has(dp)){seen.add(dp);entries.push({name:d,full:dp,dir:true});}}
    #|  }
    #|  entries.sort((a,b)=>a.dir===b.dir?a.name.localeCompare(b.name):(a.dir?-1:1));
    #|  title.textContent=path?path+'/':'/';
    #|  if(!entries.length){content.innerHTML='<p>(empty)</p>';return;}
    #|  let h='<ul class="browse-list">';
    #|  if(path){const p=path.includes('/')?path.slice(0,path.lastIndexOf('/')):'';h+='<li><a href="'+WS_PREFIX+'/'+p+'" data-spa>..</a></li>';}
    #|  for(const e of entries){h+='<li><a href="'+WS_PREFIX+'/'+e.full+'" data-spa>'+(e.dir?'\u{1F4C1} '+e.name+'/':'\u{1F4C4} '+e.name)+'</a></li>';}
    #|  h+='</ul>';
    #|  content.innerHTML=h;
    #|}
    #|
    #|// --- File view ---
    #|let _editPath=null;
    #|function renderFile(path,text,title,content){
    #|  _editPath=path;
    #|  title.textContent=path;
    #|  content.innerHTML='<div class="file-toolbar"><button class="btn btn-sm" onclick="startEdit()">Edit</button></div><pre class="source-code"><code>'+esc(text)+'</code></pre>';
    #|}
    #|async function startEdit(){
    #|  const c=document.getElementById('spa-content');
    #|  const text=await idbGet(KEY_PFX+_editPath)||'';
    #|  c.innerHTML='<div class="file-toolbar"><button class="btn btn-sm" onclick="saveEdit()">Save</button> <button class="btn btn-sm btn-secondary" onclick="navigate(subPath(),false)">Cancel</button></div><textarea id="editor">'+esc(text)+'</textarea>';
    #|  const ta=document.getElementById('editor');
    #|  ta.addEventListener('keydown',e=>{if(e.key==='Tab'){e.preventDefault();const s=ta.selectionStart,end=ta.selectionEnd;ta.value=ta.value.substring(0,s)+'  '+ta.value.substring(end);ta.selectionStart=ta.selectionEnd=s+2;}});
    #|}
    #|async function saveEdit(){
    #|  const ta=document.getElementById('editor');
    #|  if(!ta)return;
    #|  await idbPut(KEY_PFX+_editPath,ta.value);
    #|  navigate(subPath(),false);
    #|}
    #|
    #|// --- Commits ---
    #|async function renderCommits(title,content){
    #|  title.textContent='commits';
    #|  const commitKeys=await idbKeys('ws:'+WS_ID+':commit:');
    #|  if(!commitKeys.length){content.innerHTML='<p>No commits cached locally.</p>';return;}
    #|  const commits=[];
    #|  for(const k of commitKeys){const v=await idbGet(k);if(v)try{commits.push(JSON.parse(v));}catch{}}
    #|  commits.sort((a,b)=>new Date(b.date)-new Date(a.date));
    #|  let h='<table class="wf-table"><thead><tr><th>SHA</th><th>Message</th><th>Author</th><th>Date</th></tr></thead><tbody>';
    #|  for(const c of commits){h+='<tr><td><code>'+esc((c.sha||'').slice(0,8))+'</code></td><td>'+esc((c.message||'').split('\n')[0])+'</td><td>'+esc(c.author||'')+'</td><td>'+esc(c.date?new Date(c.date).toLocaleDateString():'')+'</td></tr>';}
    #|  h+='</tbody></table>';
    #|  content.innerHTML=h;
    #|}
    #|
    #|// --- SPA link interception ---
    #|document.addEventListener('click',e=>{
    #|  const a=e.target.closest('a[data-spa],nav.site-nav-repo a');
    #|  if(!a)return;
    #|  const href=a.getAttribute('href');
    #|  if(!href||!href.startsWith(WS_PREFIX))return;
    #|  e.preventDefault();
    #|  const path=href.slice(WS_PREFIX.length+1);
    #|  navigate(path,true);
    #|});
    #|window.addEventListener('popstate',()=>navigate(subPath(),false));
    #|
    #|// Initial render
    #|navigate(subPath(),false);
    #|</script>
  let spa_css =
    #|<style>
    #|.browse-list{list-style:none;padding:0;}.browse-list li{padding:4px 0;border-bottom:1px solid var(--border);}
    #|.browse-list a{text-decoration:none;color:var(--link);display:block;padding:4px 8px;border-radius:4px;}
    #|.browse-list a:hover{background:var(--pre);}
    #|.btn-sm{padding:4px 12px;font-size:13px;background:#238636;color:#fff;border:none;border-radius:4px;cursor:pointer;}
    #|.btn-sm:hover{background:#2ea043;}
    #|.btn-secondary{background:var(--panel);color:var(--text);border:1px solid var(--border);}
    #|.btn-secondary:hover{background:var(--pre);}
    #|.file-toolbar{display:flex;gap:8px;margin:8px 0;}
    #|#editor{width:100%;min-height:400px;font-family:ui-monospace,Menlo,monospace;font-size:13px;line-height:1.5;background:var(--pre);color:var(--text);border:1px solid var(--border);border-radius:6px;padding:12px;resize:vertical;tab-size:2;box-sizing:border-box;}
    #|</style>
  render_layout(
    "workspace",
    [
      @luna.h("h1", [("id", @luna.attr_static("spa-title"))], [
        @luna.text("loading..."),
      ]),
      @luna.h("div", [("id", @luna.attr_static("spa-content"))], [
        @luna.text("loading..."),
      ]),
      @luna.raw_html(
        "<script>document.body.dataset.wsPrefix='" + prefix + "';document.body.dataset.wsId='" + ws + "';</script>",
      ),
    ],
  ) + spa_css + spa_js
}

