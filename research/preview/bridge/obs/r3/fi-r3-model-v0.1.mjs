// Research-only deterministic R3 model. Execute: node fi-r3-model-v0.1.mjs
function runR3(){
  "use strict";
  // Synthetic deterministic model. No OS pipes, clocks, cryptography or actual assets.
  const results=[];
  const ok=(x,m="assertion")=>{if(!x)throw Error(m)};
  const reject=(f)=>{try{f()}catch(e){return true}return false};
  function test(name,f){try{f();results.push({name,pass:true})}catch(e){results.push({name,pass:false,error:String(e.message)})}}
  const clone=x=>JSON.parse(JSON.stringify(x));
  const common=["schema","kind","payload_bytes","release_set_id","worker_uuid"];
  const idkeys=["launch_uuid","capture_generation","frame_seq","request_uuid","captured_monotonic_ns","source_profile_id","frame_sha256","asset_digest"];
  const uuid=x=>typeof x==="string"&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(x);
  const sha=x=>typeof x==="string"&&/^[0-9a-f]{64}$/.test(x);
  const u64=x=>typeof x==="string"&&/^(0|[1-9][0-9]{0,19})$/.test(x)&&BigInt(x)<=18446744073709551615n;
  const integer=(x,a,b)=>Number.isInteger(x)&&x>=a&&x<=b;
  const keys=(o,ks)=>o!==null&&typeof o==="object"&&!Array.isArray(o)&&Object.keys(o).sort().join("\0")===ks.slice().sort().join("\0");
  const SC="champions-preview-ipc-v1.1", F="pv16-pv11-hybrid-research-v1";
  const release="a".repeat(64),asset="b".repeat(64),cal="c".repeat(64),mapping="d".repeat(64),frameHash="e".repeat(64);
  const launch="00000000-0000-4000-8000-000000000001", worker="00000000-0000-4000-8000-000000000002", request="00000000-0000-4000-8000-000000000003";
  const scoreKind="joint25-dynamic-gallery-recovery-v2";
  const ids=new Set(["mock-a","mock-b","mock-c"]);
  const types=new Set("Bug Dark Dragon Electric Fairy Fighting Fire Flying Ghost Grass Ground Ice Normal Poison Psychic Rock Steel Water NONE UNKNOWN".split(" "));
  const C={schema:SC,release_set_id:release,worker_uuid:worker};
  const I={launch_uuid:launch,capture_generation:"0",frame_seq:"1",request_uuid:request,captured_monotonic_ns:"10",source_profile_id:"replay_mock",frame_sha256:frameHash,asset_digest:asset};
  const ready={...C,kind:"ready",payload_bytes:0,launch_uuid:launch,asset_digest:asset,calibration_digest:cal,mapping_digest:mapping,score_kind:scoreKind,status:"ready"};
  const q={...C,...I,kind:"analyze",payload_bytes:24,encoding:"png",width:1,height:1};
  const held={schema:F,route:"held",reason:"pv11_no_unique_layout",status:"held",accepted:false,scene_authenticated:false,slots:Array(6).fill(null),types:null,recovered:null};
  const ranked={...held,route:"full",reason:"full_layout_candidate",status:"ranked",slots:[ [["mock-a",0.1],["mock-b",0.2]],null,null,null,null,null],types:Array.from({length:6},()=>["NONE","UNKNOWN"]),recovered:Array(6).fill(false)};
  const response={...C,...I,kind:"result",payload_bytes:0,result:ranked,elapsed_analysis_ms:1};
  function strictASCIIJSON(s){
    // Deliberately narrower than production UTF-8: all mock protocol fields ASCII.
    // Reject escaped lone surrogates and duplicate keys (including escaped spelling).
    ok(typeof s==="string"&&/^[\x20-\x7e\t\r\n]*$/.test(s),"non-ASCII mock header");
    let i=0;const ws=()=>{while(i<s.length&&/[ \t\r\n]/.test(s[i]))i++};
    function str(){ws();ok(s[i]==='"',"string");let start=i++;while(i<s.length){const c=s[i++];if(c==='"'){const v=JSON.parse(s.slice(start,i));ok(/^[\x20-\x7e]*$/.test(v),"non-ASCII decoded token");return v}if(c==="\\"){ok(i<s.length);i++}}throw Error("unterminated")}
    function value(depth){ok(depth<=20,"depth");ws();const c=s[i];if(c==="{"){i++;const o=Object.create(null);ws();if(s[i]==="}"){i++;return o}while(true){const k=str();ok(!Object.prototype.hasOwnProperty.call(o,k),"duplicate");ws();ok(s[i++]===":");o[k]=value(depth+1);ws();const sep=s[i++];if(sep==="}")return o;ok(sep===",")}}if(c==="["){i++;const a=[];ws();if(s[i]==="]"){i++;return a}while(true){a.push(value(depth+1));ws();const sep=s[i++];if(sep==="]")return a;ok(sep===",")}}if(c==='"')return str();const m=/^(true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(s.slice(i));ok(m);i+=m[0].length;const v=JSON.parse(m[0]);ok(typeof v!=="number"||Number.isFinite(v),"nonfinite");return v}
    const v=value(0);ws();ok(i===s.length,"trailing");ok(v&&typeof v==="object"&&!Array.isArray(v),"object");return v;
  }
  function fcheck(r){
    ok(keys(r,["schema","route","reason","status","accepted","scene_authenticated","slots","types","recovered"]));
    ok(r.schema===F&&r.accepted===false&&r.scene_authenticated===false&&Array.isArray(r.slots)&&r.slots.length===6);
    if(r.status==="held"){ok(r.route==="held"&&["invalid_input","explicit_visibility_rejection","pv11_unsupported_resolution","pv11_no_unique_layout","invalid_panel_bounds","sprite_flat_patch"].includes(r.reason)&&r.slots.every(x=>x===null)&&r.types===null&&r.recovered===null);return}
    ok(r.status==="ranked"&&((r.route==="full"&&r.reason==="full_layout_candidate")||(r.route==="pv11_fixed_visible"&&["pv11_layout_0","pv11_layout_1"].includes(r.reason))));
    ok(Array.isArray(r.types)&&r.types.length===6&&r.types.every(t=>Array.isArray(t)&&t.length===2&&t.every(x=>types.has(x))));
    ok(Array.isArray(r.recovered)&&r.recovered.length===6&&r.recovered.every(x=>typeof x==="boolean"));
    r.slots.forEach((a,j)=>{if(a===null){ok(!r.recovered[j]);return}ok(Array.isArray(a)&&a.length>=1&&a.length<=5);const seen=new Set;let prev=null;for(const t of a){ok(Array.isArray(t)&&t.length===2&&ids.has(t[0])&&typeof t[1]==="number"&&Number.isFinite(t[1])&&t[1]>=0&&!seen.has(t[0]));ok(!prev||prev[1]<t[1]||(prev[1]===t[1]&&prev[0]<t[0]));seen.add(t[0]);prev=t}});
  }
  function header(h,expected=q){
    ok(h.schema===SC&&h.release_set_id===release&&h.worker_uuid===worker&&uuid(h.worker_uuid)&&integer(h.payload_bytes,0,16777216));
    if(h.kind==="ready"){ok(keys(h,[...common,"launch_uuid","asset_digest","calibration_digest","mapping_digest","score_kind","status"]));ok(h.payload_bytes===0&&h.launch_uuid===launch&&h.asset_digest===asset&&h.calibration_digest===cal&&h.mapping_digest===mapping&&h.score_kind===scoreKind&&h.status==="ready");return}
    const suffix=h.kind==="analyze"?["encoding","width","height"]:h.kind==="result"?["result","elapsed_analysis_ms"]:h.kind==="error"?["error_code"]:null;ok(suffix&&keys(h,[...common,...idkeys,...suffix]));
    ok(h.launch_uuid===launch&&uuid(h.request_uuid)&&u64(h.capture_generation)&&u64(h.frame_seq)&&u64(h.captured_monotonic_ns)&&h.source_profile_id==="replay_mock"&&sha(h.frame_sha256)&&h.asset_digest===asset);
    if(h.kind==="analyze"){ok(h.encoding==="png"&&integer(h.width,1,4096)&&integer(h.height,1,4096)&&h.width*h.height<=16777216&&h.payload_bytes>0);return}
    ok(h.payload_bytes===0&&idkeys.every(k=>h[k]===expected[k]));
    if(h.kind==="result"){ok(typeof h.elapsed_analysis_ms==="number"&&Number.isFinite(h.elapsed_analysis_ms)&&h.elapsed_analysis_ms>=0);fcheck(h.result)}
    else ok(["decode_error","asset_error","analysis_error","contract_error"].includes(h.error_code));
  }
  // Synthetic PNG signature+IHDR prefix only; not a decodable PNG.
  const payload=[137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,1,0,0,0,1];
  function frame(h,p=[]){const b=JSON.stringify(h).split("").map(x=>x.charCodeAt(0));const n=b.length;return [n>>>24,(n>>>16)&255,(n>>>8)&255,n&255,...b,...p]}
  function read(a,expected=q){ok(Array.isArray(a)&&a.every(x=>integer(x,0,255))&&a.length>=4);const n=a[0]*16777216+a[1]*65536+a[2]*256+a[3];ok(integer(n,1,16384)&&a.length>=4+n);const h=strictASCIIJSON(String.fromCharCode(...a.slice(4,4+n)));header(h,expected);ok(a.length===4+n+h.payload_bytes,"length");if(h.kind==="analyze"){const p=a.slice(4+n);ok(p.length>=24&&p.slice(0,16).every((v,i)=>v===payload[i]));const w=p[16]*16777216+p[17]*65536+p[18]*256+p[19],z=p[20]*16777216+p[21]*65536+p[22]*256+p[23];ok(w===h.width&&z===h.height);ok(h.frame_sha256===frameHash&&p.length===payload.length&&p.every((v,i)=>v===payload[i]),"mock digest oracle")};return h}
  // All time and scheduling synthetic. Exactly one current decision record.
  class Authority{
    constructor(mode="shadow"){this.mode=mode;this.g=0;this.s=0;this.seq=0;this.current=null;this.active=false;this.last=-1;this.seen=new Set;this.applied=[];this.observed=["fact"];this.corrections=["user"];this.term=[]}
    boundary(active){if(this.current){this.term.push("invalidated");this.current=null}this.s++;this.active=active;this.seen.clear()}
    discontinuity(){this.g++;this.boundary(false)}
    offer(now,hash){ok(!this.current);const a=Object.freeze({g:this.g,n:++this.seq,hash,deadline:now+250,age:now+500});this.current={a,s:null,done:false};return a}
    bind(a,trusted){const c=this.current;if(c&&c.a===a&&this.active&&trusted&&c.s===null){c.s=this.s;return true}return false}
    result(a,now){const c=this.current;if(!c||c.a!==a||c.done||a.g!==this.g||c.s!==this.s||!this.active||now>=a.deadline||now>=a.age)return false;c.done=true;if(this.seen.has(a.hash))return false;this.seen.add(a.hash);if(this.mode==="shadow")return false;this.applied.push([this.s,a.n]);return true}
    close(){if(this.current){this.term.push(this.current.done?"completed":"closed");this.current=null}}
  }
  class Queue{
    constructor(){this.inflight=null;this.pending=null;this.out=new Map}
    finish(x,why){ok(!this.out.has(x.id));this.out.set(x.id,why)}
    offer(x){if(this.pending)this.finish(this.pending,"replaced");this.pending=x}
    start(now){if(this.inflight||!this.pending)return null;const x=this.pending;this.pending=null;if(now>=x.deadline){this.finish(x,"expired");return null}this.inflight=x;return x}
    done(now){const x=this.inflight;ok(x);this.inflight=null;this.finish(x,now>=x.deadline?"expired":"completed")}
    cancel(){for(const x of [this.inflight,this.pending])if(x)this.finish(x,"cancelled");this.inflight=this.pending=null}
  }
  class Consumer{
    constructor(s){this.s=s;this.rev=-1;this.digest=null;this.slots=Array(6).fill(null);this.facts=["fact"];this.corrections=["user"];this.disabled=false;this.inferences=[]}
    clear(){this.slots=Array(6).fill(null);this.inferences=[]}
    receive(x){if(this.disabled||x.s!==this.s||!Number.isSafeInteger(x.rev)||x.rev<0)return false;if(x.rev<this.rev)return false;if(x.rev===this.rev){if(x.digest!==this.digest){this.clear();this.disabled=true}return false}if(!Array.isArray(x.slots)||x.slots.length!==6||!["provisional","withdrawn","closed"].includes(x.disposition)||x.slots.some(v=>v!==null&&!ids.has(v))||(x.disposition!=="provisional"&&x.slots.some(v=>v!==null))){this.clear();this.disabled=true;return false}
      const occupied=x.slots.filter(v=>v!==null);if(new Set(occupied).size!==occupied.length){this.clear();this.disabled=true;return false}this.rev=x.rev;this.digest=x.digest;this.slots=x.slots.slice();this.inferences=occupied.map(v=>"soft:"+v);if(x.disposition==="closed")this.disabled=true;return true}
    unavailable(){this.clear();this.disabled=true}
  }
  class Release{
    constructor(){this.pointer="old";this.stage=null;this.verified=false;this.phase="idle";this.ready=false;this.published=false}
    prepare(id){this.stage=id;this.verified=false;this.ready=false}
    verify(matches){this.verified=matches;this.ready=matches}
    commit({idle,pending,reaped}){if(!this.ready||!idle||pending||!reaped)return false;this.pointer=this.stage;this.ready=false;this.published=false;return true}
    handshake(participants){this.ready=participants.length===4&&participants.every(v=>v===this.pointer);this.published=this.ready;return this.ready}
    recover(idle){if(this.ready)return "coherent";if(idle){this.pointer="old";this.published=false;return "rollback"}this.published=false;return "blocked"}
  }
  const mutate=(obj,k,v)=>({...clone(obj),[k]:v});
  test("ready",()=>ok(read(frame(ready)).kind==="ready"));
  test("request prefix and mock digest",()=>ok(read(frame(q,payload)).kind==="analyze"));
  test("ranked response",()=>ok(read(frame(response)).result.status==="ranked"));
  test("held response",()=>read(frame(mutate(response,"result",held))));
  test("fallback routes 0/1",()=>{for(const j of [0,1])read(frame(mutate(response,"result",{...ranked,route:"pv11_fixed_visible",reason:"pv11_layout_"+j})))});
  for(const [k,v] of [["release_set_id","f".repeat(64)],["worker_uuid",launch],["calibration_digest",asset],["mapping_digest",cal],["score_kind","wrong"],["status","wrong"],["payload_bytes",1]])test("ready reject "+k,()=>ok(reject(()=>read(frame(mutate(ready,k,v))))));
  for(const [k,v] of [["width",true],["height",4097],["capture_generation","01"],["frame_seq","18446744073709551616"],["request_uuid","bad"],["encoding","jpg"],["frame_sha256",asset],["source_profile_id","other"],["semantic_session","x"],["payload_bytes",23]])test("request reject "+k,()=>ok(reject(()=>read(frame(mutate(q,k,v),payload)))));
  for(const k of idkeys)test("result echo "+k,()=>ok(reject(()=>read(frame(mutate(response,k,"bad"))))));
  test("error envelope",()=>{const e={...C,...I,kind:"error",payload_bytes:0,error_code:"analysis_error"};read(frame(e));ok(reject(()=>read(frame({...e,result:held}))))});
  for(const [k,v] of [["accepted",true],["scene_authenticated",true],["route","held"],["reason","pv11_layout_2"],["slots",Array(5).fill(null)],["slots",[[["mock-x",0]],null,null,null,null,null]],["slots",[[["mock-a",0.2],["mock-b",0.1]],null,null,null,null,null]],["slots",[[["mock-a",0.1],["mock-a",0.2]],null,null,null,null,null]],["types",Array(6).fill(["none","UNKNOWN"])],["recovered",[false,true,false,false,false,false]]])test("F invalid "+k+":"+JSON.stringify(v).slice(0,30),()=>ok(reject(()=>read(frame(mutate(response,"result",mutate(ranked,k,v)))))));
  test("wrong held shape",()=>ok(reject(()=>read(frame(mutate(response,"result",{...held,slots:ranked.slots}))))));
  for(const s of ['{"a":1,"a":2}','{"a":1,"\\u0061":2}','{"a":1e999}','{"a":"\\ud800"}','{"a":1}x','[1]','{"a":01}','{"a":NaN}'])test("strict mock JSON "+s,()=>ok(reject(()=>strictASCIIJSON(s))));
  test("truncated frames",()=>{const b=frame(q,payload);for(let i=0;i<b.length;i++)ok(reject(()=>read(b.slice(0,i))))});
  test("oversize header",()=>ok(reject(()=>read([0,0,64,1]))));
  test("tampered payload",()=>{const p=payload.slice();p[23]=2;ok(reject(()=>read(frame(q,p))))});
  test("trailing payload",()=>ok(reject(()=>read([...frame(q,payload),0]))));
  test("new frame before semantic binding",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");ok(!a.result(x,1));ok(a.bind(x,true));ok(a.result(x,2));ok(!a.result(x,3))});
  test("first preview boundary invalidates old pending",()=>{const a=new Authority("model-f");const x=a.offer(0,"x");a.boundary(true);ok(!a.bind(x,true)&&!a.result(x,1));const y=a.offer(2,"y");ok(a.bind(y,true)&&a.result(y,3))});
  test("OCR unknown / untrusted",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");ok(!a.bind(x,false)&&!a.result(x,1))});
  test("cancel and rematch",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");a.bind(x,true);a.boundary(false);a.boundary(true);const y=a.offer(2,"y");a.bind(y,true);ok(!a.result(x,3)&&a.result(y,3))});
  test("discontinuity",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");a.bind(x,true);a.discontinuity();ok(!a.result(x,1)&&a.observed[0]==="fact")});
  test("deadline inclusive",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");a.bind(x,true);ok(!a.result(x,250))});
  test("closed late response",()=>{const a=new Authority("model-f");a.boundary(true);const x=a.offer(0,"x");a.bind(x,true);a.close();ok(!a.result(x,1))});
  test("duplicate content",()=>{const a=new Authority("model-f");a.boundary(true);let x=a.offer(0,"same");a.bind(x,true);ok(a.result(x,1));a.close();x=a.offer(2,"same");a.bind(x,true);ok(!a.result(x,3))});
  test("shadow never applies",()=>{const a=new Authority;const orig=JSON.stringify([a.observed,a.corrections]);a.boundary(true);const x=a.offer(0,"x");a.bind(x,true);ok(!a.result(x,1)&&a.applied.length===0&&orig===JSON.stringify([a.observed,a.corrections]))});
  test("queue pressure exact terminal accounting",()=>{const q=new Queue;q.offer({id:0,deadline:10});q.start(0);for(let i=1;i<=1000;i++){q.offer({id:i,deadline:10});ok(q.inflight.id===0&&q.pending.id===i)}q.done(1);q.start(2);q.done(3);ok(q.out.size===1001&&q.out.get(1)==="replaced"&&q.out.get(1000)==="completed")});
  test("queue expiry and cancellation",()=>{const q=new Queue;q.offer({id:0,deadline:1});ok(q.start(1)===null);q.offer({id:1,deadline:5});q.start(2);q.offer({id:2,deadline:6});q.cancel();ok([...q.out.values()].join()==="expired,cancelled,cancelled")});
  const snap=(rev,slots,disposition="provisional",s=1,digest="mock-"+rev)=>({s,rev,slots,disposition,digest});
  const empty=()=>Array(6).fill(null), one=()=>["mock-a",null,null,null,null,null];
  test("withdraw retraction and fact preservation",()=>{const c=new Consumer(1);ok(c.receive(snap(1,one()))&&c.inferences.length===1);ok(c.receive(snap(2,empty(),"withdrawn"))&&c.inferences.length===0&&c.facts[0]==="fact"&&c.corrections[0]==="user")});
  test("partial snapshot replaces old candidates",()=>{const c=new Consumer(1);c.receive(snap(1,one()));c.receive(snap(2,[null,"mock-b",null,null,null,null]));ok(c.slots[0]===null&&c.inferences.join()==="soft:mock-b")});
  test("stale and duplicate revision",()=>{const c=new Consumer(1);c.receive(snap(2,one()));ok(!c.receive(snap(1,empty()))&&!c.receive(snap(2,one()))&&c.inferences.length===1)});
  test("same revision different digest",()=>{const c=new Consumer(1);c.receive(snap(1,one()));ok(!c.receive(snap(1,empty(),"withdrawn",1,"different"))&&c.disabled&&c.inferences.length===0)});
  test("wrong session ignored",()=>{const c=new Consumer(1);ok(!c.receive(snap(1,one(),"provisional",2))&&c.inferences.length===0)});
  test("invalid candidate duplicate",()=>{const c=new Consumer(1);ok(!c.receive(snap(1,["mock-a","mock-a",null,null,null,null]))&&c.disabled)});
  test("withdrawal cannot contain candidates",()=>{const c=new Consumer(1);ok(!c.receive(snap(1,one(),"withdrawn"))&&c.disabled)});
  test("consumer restart and unavailable",()=>{let c=new Consumer(1);c.receive(snap(1,one()));c=new Consumer(1);ok(c.inferences.length===0);c.receive(snap(2,one()));c.unavailable();ok(c.inferences.length===0&&c.facts[0]==="fact"&&c.disabled)});
  test("release stage failure preserves pointer",()=>{const r=new Release;r.prepare("new");r.verify(false);ok(!r.commit({idle:true,pending:false,reaped:true})&&r.pointer==="old")});
  test("release boundary gates exhaustive combinations",()=>{for(const idle of [false,true])for(const pending of [false,true])for(const reaped of [false,true]){const r=new Release;r.prepare("new");r.verify(true);ok(r.commit({idle,pending,reaped})===(idle&&!pending&&reaped));ok(r.pointer===(idle&&!pending&&reaped?"new":"old"))}});
  test("mixed release rejected and rollback",()=>{const r=new Release;r.prepare("new");r.verify(true);r.commit({idle:true,pending:false,reaped:true});ok(!r.handshake(["new","new","old","new"])&&!r.published&&r.recover(true)==="rollback"&&r.pointer==="old")});
  test("coherent release handshake",()=>{const r=new Release;r.prepare("new");r.verify(true);r.commit({idle:true,pending:false,reaped:true});ok(r.handshake(Array(4).fill("new"))&&r.published)});
  test("unsafe rollback blocked",()=>{const r=new Release;r.prepare("new");r.verify(true);r.commit({idle:true,pending:false,reaped:true});ok(r.recover(false)==="blocked"&&!r.published)});
  return {schema:"fi-r3-synthetic-model-v0.1",scope:"deterministic synthetic in-memory JS model; no OS IPC, actual cryptographic digest, PNG decoding, Swift, Python, assets, UI or filesystem release transaction",total:results.length,passed:results.filter(x=>x.pass).length,failed:results.filter(x=>!x.pass).length,results};
}
const report=runR3();
console.log(JSON.stringify(report,null,2));
if(report.failed) process.exitCode=1;
