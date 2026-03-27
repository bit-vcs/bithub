///|
priv struct PageHtml {
  status : Int
  html : String
}


///|
fn render_layout(
  title : String,
  content : Array[@luna.Node[Unit, String]],
) -> String {
  let nav_links : Array[@luna.Node[Unit, String]] = [
    @components.link("/", [@luna.text("home")]),
    @luna.text(" | "),
    @components.link("/readme", [@luna.text("README")]),
    @luna.text(" | "),
    @components.link("/filer", [@luna.text("filer")]),
    @luna.text(" | "),
    @components.link("/commits", [@luna.text("commits")]),
    @luna.text(" | "),
    @components.link("/branches", [@luna.text("branches")]),
    @luna.text(" | "),
    @components.link("/issues", [@luna.text("issues")]),
    @luna.text(" | "),
    @components.link("/pulls", [@luna.text("pulls")]),
    @luna.text(" | "),
    @components.link("/activity", [@luna.text("activity")]),
    @luna.text(" | "),
    @components.link("/search?q=", [@luna.text("search")]),
    @luna.text(" | "),
    @components.link("/actions", [@luna.text("actions")]),
  ]
  let page = @luna.fragment([
    @components.banner([
      @luna.h("div", [("class", @luna.attr_static("site-banner"))], [
        @luna.h("strong", [("class", @luna.attr_static("site-title"))], [
          @components.link("/", [@luna.text("bithub")]),
        ]),
        @luna.h(
          "nav",
          [
            ("class", @luna.attr_static("site-nav")),
            ("aria-label", @luna.attr_static("navigation")),
          ],
          nav_links,
        ),
      ]),
    ]),
    @components.main_content([
      @components.region(aria_label="page content", content),
    ]),
    @components.contentinfo([@luna.text("rendered by sol + luna components")]),
  ])
  let css =
    #|:root{color-scheme:light dark;--bg:#f8fafc;--panel:#ffffff;--text:#0f172a;--link:#1d4ed8;--border:#d1d5db;--pre:#f3f4f6;}
    #|@media (prefers-color-scheme: dark){:root{--bg:#0b1220;--panel:#111a2e;--text:#dbe7ff;--link:#7cb3ff;--border:#2a3653;--pre:#0f172a;}}
    #|html{height:100%;}
    #|body{margin:0;height:100%;box-sizing:border-box;background:var(--bg);color:var(--text);font-family:ui-sans-serif,system-ui,sans-serif;padding:90px 14px 34px;}
    #|header{position:fixed;top:0;left:0;right:0;z-index:10;background:var(--panel);border-bottom:1px solid var(--border);padding:8px 14px;}
    #|.site-banner{display:flex;gap:10px;align-items:center;flex-wrap:wrap;}
    #|.site-title{font-size:18px;}.site-title a{text-decoration:none;}
    #|.site-nav-repo{font-size:13px;padding:4px 0 0;border-top:1px solid var(--border);margin-top:4px;}
    #|main{max-width:980px;margin:0 auto;min-height:calc(100vh - 120px);background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:16px;}
    #|footer{position:fixed;left:0;right:0;bottom:0;background:var(--panel);border-top:1px solid var(--border);padding:4px 14px;font-size:12px;}
    #|a{color:var(--link);}
    #|pre.source-code{overflow:auto;background:var(--pre);padding:12px;border-radius:6px;}
    #|.diff-add{color:#22863a;background:#f0fff4;}
    #|.diff-del{color:#cb2431;background:#ffeef0;}
    #|@media (prefers-color-scheme: dark){.diff-add{color:#85e89d;background:#144620;}.diff-del{color:#f97583;background:#3c1f23;}}
    #|code{font-family:ui-monospace,Menlo,monospace;}
    #|.wf-table{width:100%;border-collapse:collapse;}.wf-table th,.wf-table td{text-align:left;padding:8px 12px;border-bottom:1px solid var(--border);}.wf-table th{font-weight:600;}
    #|@media (max-width: 760px){body{padding:64px 10px 12px;height:auto;}main{min-height:auto;}footer{position:static;margin-top:12px;padding:8px 0 0;border-top:none;}}
  let terminal_css =
    #|#terminal-panel{display:none;position:fixed;bottom:0;left:0;right:0;height:40vh;z-index:100;background:#0d1117;border-top:2px solid #30363d;font-family:ui-monospace,Menlo,monospace;font-size:14px;color:#c9d1d9;overflow:hidden;}
    #|#terminal-panel.open{display:flex;flex-direction:column;}
    #|#terminal-bar{display:flex;justify-content:space-between;align-items:center;padding:4px 12px;background:#161b22;border-bottom:1px solid #30363d;font-size:12px;color:#8b949e;}
    #|#terminal-bar button{background:none;border:none;color:#8b949e;cursor:pointer;font-size:14px;padding:4px 8px;}
    #|#terminal-bar button:hover{color:#c9d1d9;}
    #|#terminal-output{flex:1;overflow-y:auto;padding:8px 12px;white-space:pre-wrap;word-break:break-all;line-height:1.5;}
    #|#terminal-input-row{display:flex;align-items:center;padding:6px 12px;background:#161b22;border-top:1px solid #30363d;gap:8px;}
    #|#terminal-prompt{color:#58a6ff;flex-shrink:0;}
    #|#terminal-input{flex:1;background:none;border:none;color:#c9d1d9;font-family:inherit;font-size:14px;outline:none;caret-color:#58a6ff;}
    #|.t-info{color:#8b949e;}.t-ok{color:#3fb950;}.t-err{color:#f85149;}.t-cmd{color:#58a6ff;}
  let terminal_js =
    #|<div id="terminal-panel">
    #|<div id="terminal-bar"><span>Terminal</span><button onclick="toggleTerminal()">✕</button></div>
    #|<div id="terminal-output"></div>
    #|<div id="terminal-input-row"><span id="terminal-prompt">$</span><input id="terminal-input" spellcheck="false" autocomplete="off" /></div>
    #|</div>
    #|<script>
    #|const P=document.getElementById('terminal-panel'),O=document.getElementById('terminal-output'),I=document.getElementById('terminal-input');
    #|function toggleTerminal(){P.classList.toggle('open');if(P.classList.contains('open')){I.focus();}}
    #|document.addEventListener('keydown',e=>{if(e.key==='`'&&e.ctrlKey){e.preventDefault();toggleTerminal();}});
    #|function tw(t,c){const d=document.createElement('div');d.textContent=t;if(c)d.className=c;O.appendChild(d);O.scrollTop=1e9;}
    #|
    #|// --- Unified Storage: File System Access API → IndexedDB fallback ---
    #|let fsRoot=null; // FileSystemDirectoryHandle or null
    #|const DB_NAME='bithub-blobs',DB_VER=1,STORE='blobs';
    #|let _dbP=null;
    #|function openDB(){if(_dbP)return _dbP;_dbP=new Promise((ok,ng)=>{const r=indexedDB.open(DB_NAME,DB_VER);r.onupgradeneeded=()=>r.result.createObjectStore(STORE);r.onsuccess=()=>ok(r.result);r.onerror=()=>{_dbP=null;ng(r.error);};});return _dbP;}
    #|async function idbGet(k){const db=await openDB();return new Promise(ok=>{const r=db.transaction(STORE).objectStore(STORE).get(k);r.onsuccess=()=>ok(r.result??null);r.onerror=()=>ok(null);});}
    #|async function idbPut(k,v){const db=await openDB();return new Promise(ok=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).put(v,k);tx.oncomplete=()=>ok();});}
    #|async function idbPutBatch(entries){const db=await openDB();return new Promise((ok,ng)=>{const tx=db.transaction(STORE,'readwrite');const s=tx.objectStore(STORE);for(const[k,v]of entries)s.put(v,k);tx.oncomplete=()=>ok();tx.onerror=()=>ng(tx.error);});}
    #|async function idbGetBatch(keys){const db=await openDB();return new Promise(ok=>{const tx=db.transaction(STORE);const s=tx.objectStore(STORE);const out=new Array(keys.length);let n=0;keys.forEach((k,i)=>{const r=s.get(k);r.onsuccess=()=>{out[i]=r.result??null;if(++n===keys.length)ok(out);};r.onerror=()=>{out[i]=null;if(++n===keys.length)ok(out);};});if(!keys.length)ok(out);});}
    #|async function idbKeys(pfx){const db=await openDB();return new Promise(ok=>{const r=db.transaction(STORE).objectStore(STORE).getAllKeys();r.onsuccess=()=>ok((r.result||[]).filter(k=>typeof k==='string'&&k.startsWith(pfx)));r.onerror=()=>ok([]);});}
    #|async function idbClear(){const db=await openDB();return new Promise(ok=>{const tx=db.transaction(STORE,'readwrite');tx.objectStore(STORE).clear();tx.oncomplete=()=>ok();});}
    #|
    #|// File System Access helpers
    #|async function fsGetDir(root,parts){let d=root;for(const p of parts){d=await d.getDirectoryHandle(p,{create:true});}return d;}
    #|async function fsRead(path){
    #|  if(!fsRoot)return null;
    #|  const parts=path.split('/');const name=parts.pop();
    #|  try{const dir=parts.length?await fsGetDir(fsRoot,parts):fsRoot;const fh=await dir.getFileHandle(name);const f=await fh.getFile();return await f.text();}
    #|  catch{return null;}
    #|}
    #|async function fsWrite(path,content){
    #|  if(!fsRoot)return;
    #|  const parts=path.split('/');const name=parts.pop();
    #|  const dir=parts.length?await fsGetDir(fsRoot,parts):fsRoot;
    #|  const fh=await dir.getFileHandle(name,{create:true});const ws=await fh.createWritable();await ws.write(content);await ws.close();
    #|}
    #|async function fsList(prefix){
    #|  if(!fsRoot)return[];
    #|  const parts=prefix?prefix.replace(/\/$/,'').split('/'):[];
    #|  const results=[];
    #|  try{
    #|    const dir=parts.length?await fsGetDir(fsRoot,parts):fsRoot;
    #|    for await(const[name,handle]of dir){results.push((prefix||'')+name+(handle.kind==='directory'?'/':''));}
    #|  }catch{}
    #|  return results;
    #|}
    #|
    #|// Unified: FS → IDB (ws-aware)
    #|const _wsId=window._termWsId||'';
    #|function _idbFileKey(k){return _wsId?'ws:'+_wsId+':file:'+k:'file:'+k;}
    #|function _idbFilePrefix(){return _wsId?'ws:'+_wsId+':file:':'file:';}
    #|async function cacheGet(key){const v=await fsRead(key);if(v!==null)return v;return idbGet(_idbFileKey(key));}
    #|async function cachePut(key,val){if(fsRoot)await fsWrite(key,val);else await idbPut(_idbFileKey(key),val);}
    #|async function cachePutBatch(entries){if(fsRoot){for(const[k,v]of entries)await fsWrite(k,v);}else await idbPutBatch(entries.map(([k,v])=>[_idbFileKey(k),v]));}
    #|async function cacheKeys(prefix){if(fsRoot)return fsList(prefix);const pfx=_idbFilePrefix()+prefix;return(await idbKeys(pfx)).map(k=>k.slice(_idbFilePrefix().length));}
    #|async function cacheClear(){if(fsRoot){/* can't clear FS easily */}else await idbClear();}
    #|function storageMode(){return fsRoot?'filesystem':'indexeddb';}
    #|
    #|// Connect FS button handler
    #|async function connectFS(){
    #|  if(!window.showDirectoryPicker)return alert('File System Access API not supported in this browser. Using IndexedDB.');
    #|  try{
    #|    fsRoot=await window.showDirectoryPicker({mode:'readwrite'});
    #|    // Persist handle in IndexedDB for re-use
    #|    await idbPut('_fs_handle',fsRoot);
    #|    document.getElementById('storage-mode').textContent='filesystem: '+fsRoot.name;
    #|  }catch{/* user cancelled */}
    #|}
    #|// Try restoring saved handle on load
    #|async function tryRestoreFS(){
    #|  const h=await idbGet('_fs_handle');
    #|  if(h&&h.queryPermission){
    #|    const perm=await h.queryPermission({mode:'readwrite'});
    #|    if(perm==='granted'){fsRoot=h;return true;}
    #|    // Try requesting
    #|    const req=await h.requestPermission({mode:'readwrite'}).catch(()=>'denied');
    #|    if(req==='granted'){fsRoot=h;return true;}
    #|  }
    #|  return false;
    #|}
    #|
    #|tryRestoreFS().then(ok=>{if(ok)document.getElementById('storage-mode').textContent='filesystem: '+fsRoot.name;});
    #|tw('bithub terminal — Ctrl-` to toggle','t-info');
    #|tw('Storage: '+storageMode()+'. Type "help" for commands.','t-info');
    #|const C={
    #|  help:()=>tw('Commands: help, clear, init <owner/repo>, cat <path>, ls [path], cache, cache-clear, sync, issues, activity, participants, repo','t-info'),
    #|  clear:()=>{O.innerHTML='';},
    #|  repo:async()=>{try{const r=await(await fetch('/_meta/repo')).json();tw(JSON.stringify(r,null,2),'t-info');}catch{tw('No repo initialized','t-err');}},
    #|  issues:()=>{window.open('/issues','_blank');tw('Opened /issues','t-info');},
    #|  cat:async(a)=>{
    #|    if(!a[0])return tw('Usage: cat <file-path>','t-err');
    #|    tw('Reading '+a[0]+'...','t-info');
    #|    const cached=await cacheGet(a[0]);
    #|    if(cached){tw('[cache hit]','t-info');tw(cached.length>2000?cached.slice(0,2000)+'...(truncated)':cached);}
    #|    else{const r=await fetch('/file?path='+encodeURIComponent(a[0]));if(r.ok){const t=await r.text();const plain=t.replace(/<[^>]*>/g,'').slice(0,2000);await cachePut(a[0],plain);tw(plain);}else tw('Not found: '+a[0],'t-err');}
    #|  },
    #|  ls:async(a)=>{
    #|    const prefix=a[0]?a[0]+'/':'';
    #|    const keys=await cacheKeys(prefix);
    #|    if(keys.length){keys.forEach(k=>tw(k));tw(keys.length+' file(s) in cache','t-info');}
    #|    else tw('No files cached. Run "init owner/repo" first.','t-info');
    #|  },
    #|  cache:async()=>{const keys=await cacheKeys('');tw(keys.length+' entries in IndexedDB cache','t-info');},
    #|  'cache-clear':async()=>{await cacheClear();tw('Cache cleared','t-ok');},
    #|  participants:async(a)=>{const r=await(await fetch('/api/participants?repo='+(a[0]||''))).json().catch(()=>({}));const p=r.participants||[];p.length?p.forEach(x=>tw(x.participant_id+' ('+x.status+')')):tw('No active participants','t-info');},
    #|  activity:async(a)=>{const r=await(await fetch('/api/activity?repo='+(a[0]||''))).json().catch(()=>({}));const e=r.envelopes||[];e.length?e.forEach(x=>tw('['+x.sender+'] '+x.topic+' '+x.id)):tw('No recent activity','t-info');},
    #|  init:async(a)=>{
    #|    if(!a[0])return tw('Usage: init owner/repo','t-err');
    #|    tw('Initializing '+a[0]+' (server + local cache)...','t-info');
    #|    const r=await(await fetch('/api/init?repo='+a[0],{method:'POST'})).json().catch(()=>({}));
    #|    if(!r.ok)return tw('Error: '+(r.error||'?'),'t-err');
    #|    tw('Server: '+r.files+' files loaded to R2','t-ok');
    #|    // Cache files locally in IndexedDB via GitHub API (batch)
    #|    tw('Caching to IndexedDB...','t-info');
    #|    const gh='https://api.github.com/repos/'+a[0];
    #|    try{
    #|      const tr=await(await fetch(gh+'/git/trees/'+(r.default_branch||'main')+'?recursive=1')).json();
    #|      const blobs=(tr.tree||[]).filter(e=>e.type==='blob'&&e.size<50000).slice(0,200);
    #|      let n=0;const CHUNK=10;
    #|      for(let c=0;c<blobs.length;c+=CHUNK){
    #|        const chunk=blobs.slice(c,c+CHUNK);
    #|        tw('Fetching '+(c+1)+'-'+Math.min(c+CHUNK,blobs.length)+'/'+blobs.length+'...','t-info');
    #|        const results=await Promise.allSettled(chunk.map(async e=>{
    #|          const b=await(await fetch(gh+'/git/blobs/'+e.sha)).json();
    #|          if(b.encoding==='base64'){const bin=Uint8Array.from(atob(b.content.replace(/\n/g,'')),c=>c.charCodeAt(0));return[e.path,new TextDecoder().decode(bin)];}
    #|          return null;
    #|        }));
    #|        const batch=results.filter(r=>r.status==='fulfilled'&&r.value).map(r=>r.value);
    #|        if(batch.length>0){await cachePutBatch(batch);n+=batch.length;}
    #|      }
    #|      tw('IndexedDB: '+n+' files cached','t-ok');
    #|    }catch(e){tw('IndexedDB cache failed: '+e.message,'t-err');}
    #|  },
    #|  sync:async(a)=>{
    #|    const keys=await cacheKeys('');
    #|    if(!keys.length)return tw('Nothing to sync','t-info');
    #|    tw('Syncing '+keys.length+' files to server...','t-info');
    #|    const files=[];
    #|    for(const k of keys){const content=await cacheGet(k);if(content!==null)files.push({path:k,content});}
    #|    const token=localStorage.getItem('bithub_token')||'tok-owner-001';
    #|    const r=await fetch('/api/files/sync',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({files})});
    #|    const data=await r.json();
    #|    tw('Synced '+(data.synced||0)+' files to server','t-ok');
    #|  },
    #|};
    #|I.addEventListener('keydown',async e=>{
    #|  if(e.key==='Enter'&&!e.isComposing){const v=I.value.trim();I.value='';if(!v)return;tw('$ '+v,'t-cmd');const[c,...a]=v.split(/\s+/);C[c]?await C[c](a):tw('Unknown: '+c+'. Type "help".','t-err');}
    #|});
    #|</script>
  let head = "<meta charset=\"utf-8\"><style>" + css + terminal_css + "</style>"
  @sol.render_page(page, title~, head~) + "<script>window._termWsId='';</script>" + terminal_js
}


///|
fn render_diff_patch(patch : String) -> @luna.Node[Unit, String] {
  if patch.length() == 0 {
    return @luna.text("")
  }
  let lines : Array[@luna.Node[Unit, String]] = []
  for line_view in patch.split("\n") {
    let line = line_view.to_string()
    let cls = if line.has_prefix("+") {
      "diff-add"
    } else if line.has_prefix("-") {
      "diff-del"
    } else {
      ""
    }
    if cls.length() > 0 {
      lines.push(
        @luna.h("span", [("class", @luna.attr_static(cls))], [
          @luna.text(line + "\n"),
        ]),
      )
    } else {
      lines.push(@luna.text(line + "\n"))
    }
  }
  @luna.h("pre", [("class", @luna.attr_static("source-code"))], [
    @luna.h("code", [], lines),
  ])
}
