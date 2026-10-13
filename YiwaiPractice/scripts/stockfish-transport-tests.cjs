const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),{test}=require('node:test');
const root=path.resolve(__dirname,'..');
function runtime() {
  let search=0;
  class Worker {
    postMessage(command) {
      const send=data=>queueMicrotask(()=>this.onmessage?.({data}));
      if(command==='uci')send('uciok');
      if(command==='isready')send('readyok');
      if(command.startsWith('go ')) {
        const [exact,bound]=search++%2===0?['e2e4','d2d4']:['e7e5','c7c5'];
        send(`info depth 17 score cp 208 nodes 298970 pv ${exact}`);
        // Reproduces the real engine's last fail-high update at its time limit.
        send(`info depth 18 score cp 197 lowerbound nodes 367711 pv ${bound}`);
        send(`bestmove ${bound}`);
      }
    }
    terminate(){}
  }
  const c={Worker,Blob,URL,setTimeout,clearTimeout}; c.window=c;c.webkit={messageHandlers:{reviewProgress:{postMessage(){}}}};vm.createContext(c);
  for(const name of ['chess','game-review','stockfish-review'])vm.runInContext(fs.readFileSync(path.join(root,'Resources',name+'.js'),'utf8'),c);
  return c;
}
test('time-limit bestmove cannot splice a bound candidate into an exact score and PV',async()=>{
  const c=runtime(),input={initialFEN:vm.runInContext('new Chess().fen()',c),history:['d2d4'],duration:450,runID:'regression'};
  const report=JSON.parse(await c.YiwaiStockfish.run(input,'',''));
  assert.equal(report.evaluations[0].best,'e2e4');
  assert.equal(report.evaluations[0].depth,17);
  assert.equal(report.evaluations[0].cp,208);
  assert.deepEqual(report.entries[0].bestPV,['e2e4']);
  assert.ok(report.entries[0].coach.why);
});
test('bounds, incomplete info, and invalid variations cannot become exact scores',()=>{
  const c=runtime();
  for(const line of ['info depth 18 score cp 12 lowerbound pv e2e4','info depth 18 score cp 12 upperbound pv e2e4','info depth 0 score cp 12 pv e2e4','info depth 12 nodes 55','info depth 12 score cp 12 pv (none)'])assert.equal(c.YiwaiUCI.exactResult(line),null);
  assert.equal(c.YiwaiUCI.exactResult('info depth 6 score mate 2 nodes 100 pv e2e4').score.type,'mate');
});
