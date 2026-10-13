// JavaScriptCore adaptation of the user-owned Seed 0.2. No Stockfish code.
var Seed = (function(){
const performance={now:()=>Date.now()};
// Knight Room Seed 0.2. Original search/evaluation implementation, no trained weights.
// Legal move generation/make/unmake: unmodified chess.js 1.4.0 (BSD-2-Clause).
// The small adapter deliberately pins its internal 0x88 move API; regression tests
// compare it with the public rules API, including castling, promotion and en passant.

const VERSION='Knight Room Seed 0.2';
const MATE=30000;
const VALUE={p:100,n:320,b:335,r:500,q:900,k:0};
const square=n=>'abcdefgh'[n&7]+(8-(n>>4));
const moveCode=m=>square(m.from)+square(m.to)+(m.promotion||'');
const moveObject=s=>({from:s.slice(0,2),to:s.slice(2,4),...(s[4]?{promotion:s[4]}:{})});
function position({fen=DEFAULT_POSITION,moves=[]}={}){
 if(typeof fen!=='string'||fen.length>150||!Array.isArray(moves)||moves.length>600)throw new Error('Invalid position');
 const board=new Chess(fen),counts=new Map([[board.hash(),1]]);
 for(const code of moves){if(typeof code!=='string'||!/^[a-h][1-8][a-h][1-8][qrbn]?$/.test(code)||board.isGameOver())throw new Error('Invalid history');board.move(moveObject(code));counts.set(board.hash(),(counts.get(board.hash())||0)+1);}
 const kings=board.board().flat().filter(p=>p?.type==='k');
 if(kings.length!==2||board.isAttacked(kings.find(p=>p.color!==board.turn()).square,board.turn()))throw new Error('Illegal king position');
 return {board,counts};
}
// White-positive, human-readable heuristic units, NOT calibrated centipawns/Elo.
function evaluate(board){
 let material=0,activity=0,shelter=0,nonPawn=0;const bishops={w:0,b:0};
 for(let i=0;i<128;i++){if(i&0x88){i+=7;continue;}const p=board._board[i];if(p&&p.type!=='p'&&p.type!=='k')nonPawn+=VALUE[p.type];}
 for(let i=0;i<128;i++){
  if(i&0x88){i+=7;continue;}const p=board._board[i];if(!p)continue;
  const sign=p.color==='w'?1:-1,file=i&7,rank=8-(i>>4),advance=p.color==='w'?rank-2:7-rank,center=7-Math.abs(file-3.5)-Math.abs(rank-4.5);
  material+=sign*VALUE[p.type];
  if(p.type==='p')activity+=sign*(Math.max(0,advance)*9+center*2);
  if(p.type==='n')activity+=sign*(center*12-(file===0||file===7?14:0));
  if(p.type==='b'){activity+=sign*center*7;bishops[p.color]++;}
  if(p.type==='r')activity+=sign*(advance===5?18:0);
  if(p.type==='q')activity+=sign*center*2;
  if(p.type==='k'){
   if(nonPawn<1800)activity+=sign*center*12;
   else{const direction=p.color==='w'?-16:16;for(const dx of [-1,0,1]){const at=i+direction+dx;if(!(at&0x88)&&board._board[at]?.color===p.color&&board._board[at]?.type==='p')shelter+=sign*15;}if((p.color==='w'?rank<=2:rank>=7)&&[1,2,6].includes(file))shelter+=sign*20;}
  }
 }
 activity+=(bishops.w>=2?25:0)-(bishops.b>=2?25:0);
 return {material,activity,shelter,total:material+activity+shelter};
}
function search(input={},options={}){
 const {board,counts}=position(input),started=performance.now();
 const limit=(value,fallback,min,max)=>Number.isFinite(value)?Math.max(min,Math.min(max,Math.floor(value))):fallback;
 const maxDepth=limit(options.maxDepth,5,1,8),maxNodes=limit(options.maxNodes,30000,1,200000),timeMs=limit(options.timeMs,1200,10,5000);
 let nodes=0,qnodes=0,legalityChecks=0,cutoffs=0,hashMoveHits=0,aborted=false;const STOP=Symbol('bounded search');
 const budget=()=>{if(typeof nativeCancelled==='function'&&nativeCancelled())throw new Error('cancelled');if(nodes>=maxNodes||performance.now()-started>=timeMs){aborted=true;throw STOP;}nodes++;};
 // Transposition hints store moves only, never scores. Draw/repetition-dependent
 // bounds cannot leak between different histories. All hints are checked legally.
 const hints=new Map(),killers=Array.from({length:64},()=>[]),history=new Int32Array(2*128*128),useOrdering=options.ordering!==false;
 const historyIndex=m=>(m.color==='w'?0:16384)+m.from*128+m.to;
 const isLegal=m=>{legalityChecks++;const us=board.turn();board._makeMove(m);const ok=!board._isKingAttacked(us);board._undoMove();return ok;};
 const push=m=>{legalityChecks++;const us=board.turn();board._makeMove(m);if(board._isKingAttacked(us)){board._undoMove();return false;}const key=board.hash();counts.set(key,(counts.get(key)||0)+1);return true;};
 const pop=()=>{const key=board.hash(),n=counts.get(key);if(n===1)counts.delete(key);else counts.set(key,n-1);board._undoMove();};
 const drawn=()=>board._halfMoves>=100||board.isInsufficientMaterial()||(counts.get(board.hash())||0)>=3;
 const order=(moves,first,ply=0)=>moves.map(m=>({m,code:moveCode(m),priority:priority(m,first,ply)})).sort((a,b)=>b.priority-a.priority||a.code.localeCompare(b.code)).map(x=>x.m);
 const priority=(m,first,ply)=>{
  const code=moveCode(m);if(code===first)return 2000000;
  if(m.captured||m.promotion)return 1000000+(m.captured?10*VALUE[m.captured]-VALUE[m.piece]:0)+(m.promotion?VALUE[m.promotion]+800:0);
  if(!useOrdering)return 0;const killer=killers[ply]?.indexOf(code);return (killer>=0?800000-killer*10000:0)+history[historyIndex(m)];
 };
 function visit(depth,alpha,beta,ply,qleft=8){
  budget();const check=board.inCheck(),pseudo=board._moves({legal:false}),key=board.hash();
  // Lazy legality avoids making every quiet move merely to discard it in
  // quiescence. A legal-move witness is still required before stand-pat/draw,
  // so stalemate and checkmate keep precedence over heuristic evaluation.
  if(!pseudo.some(isLegal))return {score:check?-MATE+ply:0,pv:[]};
  if(drawn())return {score:0,pv:[]};
  const staticScore=()=>evaluate(board).total*(board.turn()==='w'?1:-1);
  if(ply>=64)return {score:staticScore(),pv:[]};
  let candidates=pseudo,best=-Infinity,line=[];
  if(depth<=0){
   qnodes++;if(qleft<=0)return {score:staticScore(),pv:[]};
   if(!check){best=staticScore();if(best>=beta)return {score:best,pv:[]};alpha=Math.max(alpha,best);candidates=pseudo.filter(m=>m.captured||m.promotion);}
  }
  const hint=useOrdering?hints.get(key):undefined;if(hint)hashMoveHits++;
  for(const move of order(candidates,hint,ply)){
   if(!push(move))continue;let result;try{result=visit(depth-1,-beta,-alpha,ply+1,depth<=0?qleft-1:qleft);}finally{pop();}
   const score=-result.score;if(score>best){best=score;line=[moveCode(move),...result.pv];}alpha=Math.max(alpha,score);if(alpha>=beta){
    cutoffs++;if(useOrdering&&depth>0&&!move.captured&&!move.promotion){const code=moveCode(move),list=killers[ply];if(list[0]!==code)killers[ply]=[code,...list.filter(c=>c!==code)].slice(0,2);const i=historyIndex(move);history[i]=Math.min(16000,history[i]+depth*depth);}
    break;
   }
  }
  if(useOrdering&&line.length){if(hints.size>=32768&&!hints.has(key))hints.delete(hints.keys().next().value);hints.set(key,line[0]);}
  return {score:best,pv:line};
 }
 const initialFen=board.fen(),allLegal=board._moves(),legal=options.searchMove?allLegal.filter(m=>moveCode(m)===options.searchMove):allLegal;if(options.searchMove&&!legal.length)throw new Error('Illegal forced move');let best={move:legal.length?moveCode(order(legal)[0]):null,score:null,pv:[],depth:0};
 if(!legal.length||drawn())best={move:null,score:!legal.length&&board.inCheck()?-MATE:0,pv:[],depth:0};
 else for(let depth=options.fixedDepth?maxDepth:1;depth<=maxDepth;depth++){
  let iteration={move:null,score:-Infinity,pv:[],depth},alpha=-Infinity;
  try{for(const move of order([...legal],best.move)){
   budget();if(!push(move))continue;let child;try{child=visit(depth-1,-Infinity,-alpha,1);}finally{pop();}
   const score=-child.score;if(score>iteration.score)iteration={move:moveCode(move),score,pv:[moveCode(move),...child.pv],depth};alpha=Math.max(alpha,score);
  }best=iteration;}catch(error){if(error!==STOP)throw error;break;}
  if(Math.abs(best.score)>=MATE-64)break;
 }
 if(board.fen()!==initialFen)throw new Error('Search state did not unwind');
 return {...best,engine:VERSION,nodes,qnodes,legalityChecks,cutoffs,hashMoveHits,elapsedMs:Math.round(performance.now()-started),limited:aborted,budget:{maxDepth,maxNodes,timeMs},evaluation:evaluate(board)};
}

return {VERSION,MATE,position,evaluate,search,moveObject};
})();
