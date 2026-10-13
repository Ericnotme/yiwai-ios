// Native bridge. chess.js 1.4.0 supplies all rules; Seed supplies bounded search.
var YiwaiChess = (function () {
  const object = code => ({from:code.slice(0,2),to:code.slice(2,4),...(code[4]?{promotion:code[4]}:{})});
  function outcome(b) {
    if (b.isCheckmate()) return {result:b.turn()==='w'?'0-1':'1-0',reason:'将死'};
    if (b.isStalemate()) return {result:'1/2-1/2',reason:'逼和'};
    if (b.isInsufficientMaterial()) return {result:'1/2-1/2',reason:'子力不足'};
    if (b.isThreefoldRepetition()) return {result:'1/2-1/2',reason:'三次重复局面（本机自动和棋）'};
    if (b.isDrawByFiftyMoves()) return {result:'1/2-1/2',reason:'五十回合规则（本机自动和棋）'};
    return {result:'*',reason:''};
  }
  function snapshot(b,m) {
    const end=outcome(b);
    return {fen:b.fen(),san:m?.san||'',from:m?.from||'',to:m?.to||'',turn:b.turn(),check:b.inCheck(),mate:b.isCheckmate(),
      result:end.result,reason:end.reason,
      pieces:b.board().flat().filter(Boolean).map(p=>({square:p.square,type:p.type,color:p.color})),
      replies:end.result==='*'?b.moves({verbose:true}).map(m=>({from:m.from,to:m.to,san:m.san,promotion:m.promotion||''})):[]};
  }
  function replay(fen,codes,each,limit=600) {
    if(!Array.isArray(codes)||codes.length>limit)throw new Error(`棋谱超出${limit}半回合的本地限制`);
    const b=new Chess(fen); if(each)each(b,null);let last;
    for(const code of codes){if(outcome(b).result!=='*')throw new Error('终局后不能继续走子');last=b.move(object(code));if(each)each(b,last);}
    return {b,last};
  }
  const safe=fn=>{try{return JSON.stringify(fn());}catch(e){return JSON.stringify({error:String(e.message||e)});}};
  function typed(raw,turn) {
    if(raw===null)return {kind:'unknown'};
    if(Math.abs(raw)>=Seed.MATE-64)return {kind:'mate',winner:raw>=0?turn:(turn==='w'?'b':'w'),mateIn:Math.ceil((Seed.MATE-Math.abs(raw))/2)};
    return {kind:'cp',cp:Math.round(raw*(turn==='w'?1:-1))};
  }
  function evidence(fen,moves,pv) {
    const {b}=replay(fen,moves);const result=[];
    for(const code of pv){if(outcome(b).result!=='*')throw new Error('变化线越过终局');const m=b.move(object(code));result.push(m.san);}
    return result;
  }
  function line(input,r) {return {score:typed(r.score,Seed.position(input).board.turn()),pv:r.pv,san:evidence(input.fen,input.moves,r.pv),depth:r.depth,nodes:r.nodes,limited:r.limited};}
  return {
    // A full 600-ply game may still have a 12-ply independent review continuation.
    inspect:(fen,codes)=>safe(()=>{const frames=[];replay(fen,codes,(b,m)=>frames.push(snapshot(b,m)),612);return {frames};}),
    game:(fen,codes,info)=>safe(()=>{
      const sans=[];const {b,last}=replay(fen,codes,(b,m)=>{if(m)sans.push(m.san);});const frame=snapshot(b,last);
      const result=frame.result!=='*'?frame.result:(info.ending==='resigned'?(info.human==='w'?'0-1':'1-0'):'*');
      const headers={Event:'Yiwai local computer game',Site:'Offline iPhone',Date:info.date||'????.??.??',Round:'-',
        White:info.human==='w'?'Player':'Seed 0.2',Black:info.human==='b'?'Player':'Seed 0.2',Result:result};
      for(const [key,value] of Object.entries(headers))b.setHeader(key,value);
      if(info.ending==='resigned')b.setHeader('Termination','resignation');
      return {frame,sans,pgn:b.pgn(),result,reason:frame.reason||(info.ending==='resigned'?'认输':info.ending==='saved'?'已保存，未结束':'')};
    }),
    search:(input,options,searchID)=>safe(()=>{
      const r=Seed.search(input,options);const {board}=Seed.position(input);
      return {searchID,fen:board.fen(),history:input.moves,move:r.move||'',line:line(input,r)};
    }),
    review:(input,played,searchID)=>safe(()=>{
      const options={maxDepth:3,maxNodes:200000,timeMs:3000,fixedDepth:true};
      const before=Seed.search(input,options);
      const after=Seed.search(input,{...options,searchMove:played});
      if(before.depth!==3||after.depth!==3)throw new Error('超出本步分析预算，未计入统计');
      const {board}=Seed.position(input),fen=board.fen(),m=board.move(object(played));
      return {searchID,fen,history:input.moves,best:line(input,before),played:line(input,after),
        moveSAN:m.san,captured:m.captured||'',promotion:m.promotion||'',check:board.inCheck(),mate:board.isCheckmate()};
    }),
    perft:(fen,depth)=>new Chess(fen).perft(depth),
    roundtrip:pgn=>safe(()=>{const b=new Chess();b.loadPgn(pgn,{strict:true});return {fen:b.fen(),sans:b.history(),result:b.getHeaders().Result};})
  };
})();
