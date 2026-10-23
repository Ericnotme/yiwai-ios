const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),vm=require('vm');
function runtime(){const c={};vm.createContext(c);for(const n of ['chess','position-import','chess-bridge'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../Resources',n+'.js'),'utf8'),c);return c;}
const fen='7k/8/5KQ1/8/8/8/8/8 w - - 0 1';
const scan=(c,f,m,s)=>JSON.parse(c.YiwaiChess.scanMissedMate(f,m,s));
test('missed mate evidence gives complete answers and actual legal defences',()=>{const c=runtime(),r=scan(c,fen,['g6g5'],'w');assert.equal(r.misses,1);assert.deepEqual(r.evidence[0].answers,['g6g7']);assert.equal(r.evidence[0].playedSAN,'Qg5');assert.deepEqual(r.evidence[0].replyExamples,['Kh7']);});
test('actual mate and no opportunity are not mistakes',()=>{const c=runtime();assert.equal(scan(c,fen,['g6g7'],'w').misses,0);const g=JSON.parse(c.YiwaiChess.importPosition('1. e4 e5 2. Nf3 Nc6 *','pgn'));assert.equal(scan(c,g.initialFen,g.moves,'w').misses,0);});
test('only explicitly selected side is analyzed; invalid selection rejected',()=>{const c=runtime();assert.equal(scan(c,fen,['g6g5'],'b').examined,0);assert.match(scan(c,fen,['g6g5'],'').error,/执棋方/);});
test('illegal, terminal continuation and oversized games do not yield partial evidence',()=>{const c=runtime();assert.ok(scan(c,fen,['g6g5','h8h6'],'w').error);assert.ok(scan(c,fen,['g6g7','h8h7'],'w').error);assert.ok(scan(c,fen,Array(601).fill('g6g5'),'w').error);});
test('promotion accepts both mating promotions, rejects neither as missed mate',()=>{const c=runtime(),f='7k/5P1p/5K2/8/8/8/8/8 w - - 0 1';assert.equal(scan(c,f,['f7f8r'],'w').misses,0);const r=scan(c,f,['f7f8n'],'w');assert.equal(r.misses,1);assert.deepEqual(r.evidence[0].answers,['f7f8q','f7f8r']);});
test('cancelled scan returns no fabricated or partial result',()=>{const c=runtime();c.nativeCancelled=()=>true;assert.match(scan(c,fen,['g6g5'],'w').error,/取消/);});
