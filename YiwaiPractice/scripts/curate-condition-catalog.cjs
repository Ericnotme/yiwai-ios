const fs=require('fs'),vm=require('vm'),path=require('path');
const root=path.resolve(__dirname,'..');
const c={};vm.createContext(c);for(const n of ['chess','position-import','chess-bridge'])vm.runInContext(fs.readFileSync(path.join(root,'Resources',n+'.js'),'utf8'),c);
const families=[
 {id:'queen-bishop',title:'后与象的协同',critical:'h5f7',capture:'h5e5',relation:'h6 黑马是否能吃掉 f7 的将军后',proofs:['1. e3 e5 2. d4 exd4 3. Bc4 a6 4. Qh5 b6 *','1. e3 e5 2. d4 a6 3. Bc4 a5 4. Qh5 b6 *','1. e3 e5 2. d4 exd4 3. Bc4 Nh6 4. Qh5 b6 *','1. e3 e5 2. d4 a6 3. Bc4 Nh6 4. Qh5 b6 *']},
 {id:'king-diagonal',title:'王前斜线的遮挡',critical:'d8h4',capture:'e5f4',relation:'g 兵是否仍遮住 h4 至 e1 的斜线',proofs:['1. f3 e5 2. g4 *','1. f4 e5 2. g4 *','1. f3 e5 2. g3 *','1. f4 e5 2. g3 *']},
 {id:'pinned-pawn',title:'能吃将军子的兵是否被牵制',critical:'e5d3',capture:'e5f3',relation:'e7 黑后是否牵制 e2 白兵，使其不能吃 d3 的马',proofs:['1. d4 Nf6 2. c4 e5 3. dxe5 Ng4 4. Nh3 Nc6 5. Bf4 Bb4+ 6. Nbd2 Qe7 7. a3 Ngxe5 8. axb4 *','1. d4 Nf6 2. c4 e5 3. dxe5 Ng4 4. Nf3 Nc6 5. Bf4 Bb4+ 6. Nbd2 Qe7 7. a3 Ngxe5 8. axb4 *','1. d4 Nf6 2. c4 e5 3. dxe5 Ng4 4. Nh3 Nc6 5. Bf4 Bb4+ 6. Nbd2 d6 7. a3 Ngxe5 8. axb4 *','1. d4 Nf6 2. c4 e5 3. dxe5 Ng4 4. Nf3 Nc6 5. Bf4 Bb4+ 6. Nbd2 d6 7. a3 Ngxe5 8. axb4 *']}
];
const positions=[];
function make(id,pgn){const a=JSON.parse(c.YiwaiChess.importPosition(pgn,'pgn'));if(a.error)throw Error(id+': '+a.error);const frames=JSON.parse(c.YiwaiChess.inspect(a.initialFen,a.moves)).frames; const frame=frames.at(-1);frame.replies.forEach(m=>{m.code=m.from+m.to+m.promotion;m.captured=m.san.includes("x");});const mates=[];for(const move of frame.replies){const check=JSON.parse(c.YiwaiChess.inspect(frame.fen,[move.code]));if(check.error)throw Error(id+' '+JSON.stringify(move)+' '+check.error);const after=check.frames.at(-1);if(after.mate&&after.replies.length===0)mates.push(move.code);}return {id,version:1,pgn,fen:frame.fen,proofMoves:a.moves,answers:mates.sort(),frame};}
for(const f of families){for(let i=0;i<4;i++){const condition='ABCD'[i],capture=i%2===1,changed=i>=2;const p=make(f.id+'-'+condition,f.proofs[i]);const move=p.frame.replies.find(m=>m.code===f.critical),distraction=p.frame.replies.find(m=>m.code===f.capture);console.log(p.id,p.answers,'critical legal',!!move,'capture',distraction);if(!move||(!changed&&(p.answers.length!==1||p.answers[0]!==f.critical))||(changed&&p.answers.length))throw Error('Answer constraint '+p.id);const isCapture=!!distraction?.captured;if(isCapture!==capture||p.answers.includes(f.capture))throw Error('Capture constraint '+p.id);delete p.frame;positions.push({...p,family:f.id,condition,captureOpportunity:capture,defenseChanged:changed,critical:f.critical,distractingCapture:f.capture,relation:f.relation});}}
const transfer=[
 ['legal','1. e4 e5 2. Nf3 d6 3. Bc4 Bg4 4. Nc3 Nc6 5. Nxe5 Bxd1 6. Bxf7+ Ke7 *',1],
 ['back-rank','1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 *',1],
 ['castled','1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 O-O 6. Nf3 h6 7. Bh4 b6 8. cxd5 Nxd5 *',0],
 ['en-passant','1. e4 a6 2. e5 d5 *',0]
];
for(const [id,pgn,count]of transfer){const p=make('transfer-'+id,pgn);console.log(p.id,p.answers,p.fen);if(p.answers.length!==count)throw Error('Transfer constraint '+id);delete p.frame;positions.push({...p,family:'transfer',condition:'transfer',captureOpportunity:false,defenseChanged:false,critical:null,distractingCapture:null,relation:'到期后在不同局面重新核对全部合法应对；不归因于某种心理特征'});}
if(new Set(positions.map(p=>p.fen.split(' ').slice(0,4).join(' '))).size!==16)throw Error('Duplicate');
const generated={schemaVersion:1,experimental:true,source:'本项目选编的合法 PGN 证明；包含经典将死结构，不宣称结构独创；只保存走法，无第三方注释',license:'GPL-3.0-or-later（本项目题目数据与说明）；第三方棋规与引擎保留原许可',families:families.map(({id,title,relation})=>({id,title,relation})),positions};
const bundled=JSON.parse(fs.readFileSync(path.join(root,'Resources/condition-catalog.json'),'utf8'));
if(JSON.stringify(generated)!==JSON.stringify(bundled))throw Error('Curated proof source differs from bundled catalog');
console.log('All 16 legal PGN proofs and condition constraints match the bundled version. Engine evidence is verified separately by native tests.');
