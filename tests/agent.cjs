const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {PassThrough}=require('node:stream');const {EventEmitter}=require('node:events');
const root=path.join(__dirname,'../packages/eschaton-agent');
const {Desktop,atomic}=require(root+'/desktop.cjs');
const clone=x=>JSON.parse(JSON.stringify(x));
function setup(t) {
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'eschaton-agent-test-'));
 t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 let bars=[{id:'default',leftWidgets:['launcher'],centerWidgets:['clock'],rightWidgets:['battery']}];let writes=0;
 const bridge=async(method,id,before,after)=>{
  if(method==='inspect') return clone(bars);
  assert.equal(id,'default');const layout=Object.fromEntries(Object.entries(bars[0]).filter(([k])=>k!=='id'));
  if(JSON.stringify(layout)!==before) throw Error('Conflit CAS');
  bars[0]={id,...JSON.parse(after)};writes++;return clone(bars[0]);
 };
 return {dir,bridge,desktop:new Desktop(dir,bridge),get bars(){return bars;},get writes(){return writes;}};
}
const move={barId:'default',widget:'clock',section:'left',index:0};
test('déplacement vérifié, journal durable, nouvelle instance et annulation',async t=>{
 const f=setup(t);const change=await f.desktop.move(move,'request');assert.equal(change.status,'verified');
 assert.deepEqual(f.bars[0].leftWidgets,['clock','launcher']);
 const restarted=new Desktop(f.dir,f.bridge);await restarted.recover();await restarted.undo(change.id);
 assert.deepEqual(f.bars[0].centerWidgets,['clock']);assert.equal(restarted.changes[0].status,'undone');
 assert.equal(fs.statSync(path.join(f.dir,'changes.json')).mode&0o777,0o600);
});
test('requête rejouée idempotente et identifiant réutilisé pour autre action refusé',async t=>{
 const f=setup(t);await f.desktop.move(move,'request');await f.desktop.move(move,'request');assert.equal(f.writes,1);
 await assert.rejects(f.desktop.move({...move,index:1},'request'),/autre action/);
});
test('annulation préserve une modification ultérieure du bureau',async t=>{
 const f=setup(t);await f.desktop.move(move,'request');f.bars[0].rightWidgets.push('weather');
 await assert.rejects(f.desktop.undo('request'),/changé/);assert.equal(f.writes,1);
});
test('arrêt après écriture avant accusé : rapprochement sans seconde écriture',async t=>{
 const f=setup(t);const desktop=new Desktop(f.dir,async(...args)=>{const value=await f.bridge(...args);if(args[0]==='apply')throw Error('timeout');return value;});
 assert.equal((await desktop.move(move,'request')).status,'verified');assert.equal(f.writes,1);
 desktop.changes[0].status='applying';desktop.save();const restarted=new Desktop(f.dir,f.bridge);await restarted.recover();
 assert.equal(restarted.changes[0].status,'verified');assert.equal(f.writes,1);
});
test('crash avant écriture ne rejoue pas une action',async t=>{
 const f=setup(t);await f.desktop.move(move,'request');await f.desktop.undo('request');
 f.desktop.changes[0].status='applying';f.desktop.save();const restarted=new Desktop(f.dir,f.bridge);await restarted.recover();
 assert.equal(restarted.changes[0].status,'not_applied');assert.equal(f.writes,2);
});
test('validation stricte et annulation avant mutation',async t=>{
 const f=setup(t);
 for(const args of [{...move,widget:'unknown'},{...move,section:';rm'},{...move,index:300},{...move,index:0.2}])
  await assert.rejects(f.desktop.move(args,JSON.stringify(args)));
 await assert.rejects(f.desktop.move(move,'cancelled',()=>false),/annulée/);assert.equal(f.writes,0);
});
test('concurrence externe entre lecture et application refusée atomiquement',async t=>{
 const f=setup(t);const desktop=new Desktop(f.dir,async(...args)=>{
  if(args[0]==='apply') f.bars[0].centerWidgets.push('weather');return f.bridge(...args);
 });
 await assert.rejects(desktop.move(move,'request'),/Conflit/);
 assert.equal(desktop.changes[0].status,'conflict');assert.equal(f.writes,0);
});
function loadAgent(dir) {
 for(const file of ['agent.cjs','desktop.cjs','status.cjs','catalog.json']) fs.copyFileSync(root+'/'+file,dir+'/'+file);
 fs.writeFileSync(dir+'/protocol.cjs',fs.readFileSync(root+'/CodexProtocol.js','utf8').replace('.pragma library','')+'\nmodule.exports={create};');
 return require(dir+'/agent.cjs').Agent;
}
function fakeCodex() {
 const child=new EventEmitter();child.stdin=new PassThrough();child.stdout=new PassThrough();child.stderr=new PassThrough();
 child.exitCode=null;child.kill=()=>{child.exitCode=0;child.emit('exit',0);};let input='';let resumed=0;
 const push=msg=>child.stdout.write(JSON.stringify(msg)+'\n');
 child.stdin.on('data',chunk=>{
  input+=chunk;let i;while((i=input.indexOf('\n'))>=0){const m=JSON.parse(input.slice(0,i));input=input.slice(i+1);
   let result={};
   if(m.method==='account/read')result={account:{type:'chatgpt',planType:'plus'}};
   if(m.method==='model/list')result={data:[{model:'test-model',isDefault:true}]};
   if(m.method==='thread/start'||m.method==='thread/resume'){result={thread:{id:'thread-test'}};if(m.method==='thread/resume')resumed++;}
   if(m.method==='turn/start')result={turn:{id:'turn-test'}};
   if(m.id!==undefined)queueMicrotask(()=>push({id:m.id,result}));
  }
 });return {child,push,get resumed(){return resumed;}};
}
const settle=()=>new Promise(r=>setTimeout(r,50));
test('agent détaché : outil exécuté sans client, historique et thread repris après redémarrage',async t=>{
 const f=setup(t),Agent=loadAgent(f.dir),engine=fakeCodex();
 const agent=new Agent(f.dir,f.desktop,()=>engine.child);t.after(()=>agent.close());
 await agent.command({id:'enable',method:'enable',params:{enabled:true}});await settle();
 assert.equal(agent.state.signedIn,true);
 await agent.command({id:'user-1',method:'send',params:{text:'Déplace l’heure à gauche'}});await settle();
 assert.equal(agent.clients.size,0);
 engine.push({id:700,method:'item/tool/call',params:{callId:'tool-1',threadId:'thread-test',turnId:'turn-test',tool:'desktop_move_widget',arguments:move}});
 await settle();assert.equal(f.writes,1);
 engine.push({method:'item/agentMessage/delta',params:{threadId:'thread-test',turnId:'turn-test',itemId:'answer',delta:'Horloge déplacée.'}});
 engine.push({method:'turn/completed',params:{threadId:'thread-test',turn:{id:'turn-test',status:'completed'}}});await settle();agent.close();
 const nextEngine=fakeCodex();const next=new Agent(f.dir,new Desktop(f.dir,f.bridge),()=>nextEngine.child);t.after(()=>next.close());next.start();await settle();
 assert.equal(next.state.messages.at(-1).content,'Horloge déplacée.');
 await next.command({id:'user-2',method:'send',params:{text:'Où est-elle ?'}});await settle();assert.equal(nextEngine.resumed,1);
 await next.command({id:'undo',method:'desktop.undo',params:{id:'user-1:tool-1'}});assert.equal(f.writes,2);
});
test('mode local arrête le réseau et interdit de relancer le login',async t=>{
 const f=setup(t),Agent=loadAgent(f.dir),engine=fakeCodex();const agent=new Agent(f.dir,f.desktop,()=>engine.child);t.after(()=>agent.close());
 await agent.command({id:'on',method:'enable',params:{enabled:true}});await settle();
 await agent.command({id:'off',method:'enable',params:{enabled:false}});assert.equal(engine.child.exitCode,0);
 await assert.rejects(agent.command({id:'login',method:'login'}),/local/);
 assert.equal(agent.disk.enabled,false);
});

test('statut : commande fixe, échec partiel visible, sortie bornée',async()=>{
 const {collect}=require(root+'/status.cjs');const calls=[];
 const status=await collect(async(program,args)=>{calls.push([program,args]);if(program.endsWith('df'))throw Error('failure');return {stdout:'x'.repeat(12000)};});
 assert.equal(calls.length,4);assert.equal(status.sources.disk.available,false);
 assert.equal(status.sources.packages.text.length,10000);assert.equal(status.sources.packages.truncated,true);
 assert.equal(status.classification,'UNTRUSTED_SYSTEM_DATA');
 assert.deepEqual(calls.find(c=>c[0].endsWith('pacman'))[1],['-Q']);
});
