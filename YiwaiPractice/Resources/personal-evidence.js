// Local standard-history proof. No storage, network, psychological inference or AI text.
(() => {
  const code=m=>m.from+m.to+(m.promotion||'');
  const object=s=>({from:s.slice(0,2),to:s.slice(2,4),...(s[4]?{promotion:s[4]}:{})});
  const check=()=>{if(typeof nativeCancelled==='function'&&nativeCancelled())throw Error('检查已暂停');};
  const safe=fn=>{try{return JSON.stringify(fn());}catch(e){return JSON.stringify({error:String(e.message||e)});}};
  function position(history){const b=new Chess();for(const m of history){check();if(b.isGameOver())throw Error('证明越过终局');b.move(object(m));}return b;}
  function mates(b){if(b.isGameOver())return [];const result=[];for(const m of b.moves({verbose:true})){check();b.move(m);if(b.isCheckmate())result.push(code(m));b.undo();}return result.sort();}
  function mainline(text){
    let result='', braces=0, variation=0, lineComment=false;
    for(const c of text){
      if(lineComment){if(c==='\n')lineComment=false;else continue;}
      if(braces){if(c==='}')braces--;continue;}
      if(c==='{'){braces++;continue;}if(c===';'){lineComment=true;continue;}
      if(c==='('){variation++;continue;}if(c===')'){if(!variation)throw Error('变例括号不匹配');variation--;continue;}
      if(!variation)result+=c;
    }
    if(braces||variation)throw Error('注释或变例未结束');return result;
  }
  YiwaiChess.personalImport=(text,side)=>safe(()=>{
    if(!['w','b'].includes(side))throw Error('请确认自己执白还是执黑');
    if(typeof text!=='string'||text.length>200000)throw Error('最多 200 KB，单盘 PGN');
    const clean=mainline(text), withoutHeaders=clean.replace(/\[[^\]\r\n]*\]/g,' ');
    if((clean.match(/\[Event\s/g)||[]).length>1||(clean.match(/\[White\s/g)||[]).length>1)throw Error('每次只分析一盘棋');
    const endings=[...withoutHeaders.matchAll(/(?:^|\s)(1-0|0-1|1\/2-1\/2|\*)(?=\s|$)/g)];
    if(endings.length>1 || endings.length===1 && withoutHeaders.slice(endings[0].index+endings[0][0].length).trim())throw Error('终局标记之后还有内容；每次只分析一盘棋');
    const parsed=YiwaiImport.parse(text,'pgn',Chess);
    if(parsed.headers.Variant&&!/^(standard|chess|normal)$/i.test(parsed.headers.Variant))throw Error('目前仅支持标准国际象棋');
    if(parsed.initialFen!==new Chess().fen())throw Error('此流程要求标准开局完整历史；FEN 棋谱可用原导入入口保存，暂不生成原因题');
    if(!parsed.moves.length||parsed.moves.length>200)throw Error('此流程支持 1–200 个半回合；不会截断棋谱');
    position(parsed.moves);return parsed;
  });
  YiwaiChess.personalBranches=(history,critical)=>safe(()=>{
    if(!history.length)return {branches:[]};
    const prefix=history.slice(0,-1),actual=history.at(-1),b=position(prefix),branches=[];
    for(const move of b.moves({verbose:true}).sort((a,b)=>code(a).localeCompare(code(b)))){
      check();if(code(move)===actual)continue;
      b.move(move);
      if(!b.isGameOver()&&b.moves({verbose:true}).some(m=>code(m)===critical)&&!mates(b).length){
        const fen=b.fen(),attempt=b.move(object(critical)),criticalReplies=b.moves();
        const criticalOutcome=b.isStalemate()?'stalemate':b.isDraw()?'draw':b.isCheck()?'check with legal replies':'ongoing';
        b.undo();
        branches.push({history:[...prefix,code(move)],fen,answers:[],replaced:actual,replacement:code(move),replacementSAN:move.san,
          critical,criticalSAN:attempt.san,criticalReplies,criticalOutcome});
      }
      b.undo();
    }
    return {branches};
  });
  YiwaiChess.personalValidate=(history,pv)=>safe(()=>{
    const b=position(history),fen=b.fen(),answers=mates(b),legal=b.moves({verbose:true}).map(code);
    for(const m of pv){if(b.isGameOver())throw Error('引擎变化越过终局');b.move(object(m));}
    return {fen,answers,legal};
  });
})();
