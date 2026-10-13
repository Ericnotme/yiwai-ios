const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),{test}=require('node:test');
const root=path.resolve(__dirname,'..'),c={};vm.createContext(c);
for(const name of ['chess','game-review'])vm.runInContext(fs.readFileSync(path.join(root,'Resources',name+'.js'),'utf8'),c);
const review=c.YiwaiReview,plain=x=>JSON.parse(JSON.stringify(x));
const fixtures=JSON.parse(fs.readFileSync(path.join(root,'Tests/Fixtures/website-accuracy.json'),'utf8')).cases;
test('website-generated golden evaluations produce identical per-move and both-player accuracy',()=>{
 for(const fixture of fixtures){
  const result=review.build({...fixture,engine:review.engine,metric:review.metric,duration:450,gameComplete:true},fixture.evaluations);
  assert.equal(result.white,fixture.expected.white,fixture.name+' white');assert.equal(result.black,fixture.expected.black,fixture.name+' black');
  assert.deepEqual(plain(result.entries.map(({ply,color,san,number,loss,rawLoss,accuracy,weight,category})=>({ply,color,san,number,loss,rawLoss,accuracy,weight,category}))),fixture.expected.entries);
 }
});
test('unknown engine, partial reports and invalid scores cannot generate accuracy',()=>{
 const f=fixtures[0],input={...f,engine:review.engine,metric:review.metric,duration:450};
 assert.throws(()=>review.build({...input,engine:'Seed 0.2'},f.evaluations),/不匹配/);
 assert.throws(()=>review.build(input,f.evaluations.slice(1)),/全部局面/);
 assert.throws(()=>review.build(input,f.evaluations.map((e,i)=>i?e:{...e,win:NaN})),/未完成/);
 assert.throws(()=>review.normalize({score:{type:'cp',value:10},depth:0},review.position(f.initialFEN,[])),/有效评分/);
});
test('forced and best moves ignore adjacent-search horizon noise',()=>{
 const f=fixtures[0],input={...f,engine:review.engine,metric:review.metric,duration:450};
 const evaluations=plain(f.evaluations);evaluations[0].win=100;evaluations[1].win=0;
 let result=review.build(input,evaluations);assert.equal(result.entries[0].loss,0);assert.equal(result.entries[0].accuracy,100);
 evaluations[0].best='d2d4';evaluations[0].pv=['d2d4'];evaluations[0].legalCount=1;
 result=review.build(input,evaluations);assert.equal(result.entries[0].loss,0);
});
test('capture with recapture is not described as net material loss',()=>{
 const info=review.coach('4k3/8/8/8/4p3/3q4/8/3RK3 w - - 0 1','d1d2',['d1d3','e4d3'],['d1d2','d3d2','e1d2']);
 assert.match(info.missed,/没有净子力损失/);assert.doesNotMatch(info.missed,/少了约/);assert.match(info.why,/净多约 4/);
});
test('en passant explains the captured pawn actual square',()=>{
 const info=review.coach('4k3/8/8/8/3p4/8/4P3/4K3 w - - 0 1','e2e4',['e1d1'],['e2e4','d4e3']);
 assert.match(info.missed,/e4 的兵/);assert.match(info.missed,/少了约 1/);
});
test('immediate mate explanation is justified by legal-move exhaustion',()=>{
 const info=review.coach('7k/8/5KQ1/8/8/8/8/8 w - - 0 1','g6g1',['g6g7'],['g6g1','h8h7']);
 assert.match(info.why,/没有任何合法应将/);assert.match(info.missed,/漏掉了一步将死/);
});
test('an alternative immediate mate is never called a missed mate',()=>{
 const info=review.coach('7k/5K2/6Q1/8/8/8/8/8 w - - 0 1','g6g8',['g6g7'],['g6g8']);
 assert.equal(info.theme,'完成将死');assert.match(info.missed,/同样直接将死/);assert.doesNotMatch(info.missed,/你漏掉/);
});
test('a line with illegal or post-mate moves is rejected, not narrated',()=>{
 assert.throws(()=>review.coach(fixtures[0].initialFEN,'e2e4',['e2e5'],['e2e4']));
 assert.throws(()=>review.coach('7k/8/5KQ1/8/8/8/8/8 w - - 0 1','g6g7',['g6g7','h8g8'],['g6g7']));
});
test('mate normalization, draws, black view, empty and zero accuracy retain website meaning',()=>{
 const b=review.position(fixtures[0].initialFEN,['e2e4']);
 assert.equal(review.normalize({score:{type:'cp',value:120},depth:12,move:'e7e5'},b).cp,-120);
 assert.equal(review.normalize({score:{type:'mate',value:3},depth:12,move:'e7e5'},b).winner,'b');
 assert.equal(review.terminal(review.position('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1',[])).win,50);
 assert.equal(review.gameAccuracy([]),null);assert.equal(review.gameAccuracy([{accuracy:100,weight:1},{accuracy:0,weight:1}]),25);
});
