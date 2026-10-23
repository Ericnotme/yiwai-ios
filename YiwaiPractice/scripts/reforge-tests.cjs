const test=require('node:test'), assert=require('node:assert/strict'),fs=require('fs'),path=require('path'),vm=require('vm');
const resources=path.join(__dirname,'../Resources'),ctx={};vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(resources,'chess.js'),'utf8')+'\nthis.RuleChess=Chess;',ctx);
vm.runInContext(fs.readFileSync(path.join(resources,'position-import.js'),'utf8'),ctx);
const puzzles=JSON.parse(fs.readFileSync(path.join(resources,'reforge-puzzles.json'),'utf8'));
for(const p of puzzles)test(p.id+' complete legal mate-in-one answers, traceable source',()=>{
 ctx.YiwaiImport.fen(p.fen,ctx.RuleChess);const b=new ctx.RuleChess(p.fen);assert.equal(b.isGameOver(),false);
 let answers=[];for(const m of b.moves({verbose:true})){b.move(m);if(b.isCheckmate()){assert.equal(b.moves().length,0);answers.push(m.from+m.to+(m.promotion||''));}b.undo();}
 assert.deepEqual(answers.sort(),p.answers.slice().sort());assert.ok(answers.length);assert.ok(p.source.includes('原创'));assert.ok(p.license.includes('GPL-3.0'));assert.equal(p.version,1);
});
test('catalog uses distinct structures; counter changes never establish novelty',()=>{
 const keys=puzzles.map(p=>p.fen.split(' ').slice(0,4).join(' '));assert.equal(new Set(keys).size,puzzles.length);
 assert.equal(puzzles.length,5);assert.equal(new Set(puzzles.map(p=>p.fen.split(' ')[0])).size,5);
 assert.deepEqual(puzzles.find(p=>p.id==='reforge-004').answers.slice().sort(),['f7f8q','f7f8r']);
});
