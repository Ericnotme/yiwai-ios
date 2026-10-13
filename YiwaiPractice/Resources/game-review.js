// Original Yiwai review/teaching code. Formula parity: Knight Room public/review.mjs.
// Requires chess.js. Engine evaluations must come from the named Stockfish build.
var YiwaiReview = (() => {
  const metric = 'knight-room-review-v1';
  const engine = 'Stockfish 19 · lite single';
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const mean = xs => xs.reduce((s, x) => s + x, 0) / xs.length;
  const moveObject = code => ({from:code.slice(0,2), to:code.slice(2,4), ...(code[4] ? {promotion:code[4]} : {})});
  const codeOf = m => m.from + m.to + (m.promotion || '');
  const pieceNames = {p:'兵',n:'马',b:'象',r:'车',q:'后',k:'王'};
  const values = {p:1,n:3,b:3,r:5,q:9,k:0};
  const winPercent = cp => 100 / (1 + Math.exp(-0.00368208 * clamp(cp,-10000,10000)));
  const moveAccuracy = loss => loss <= 0 ? 100 : clamp(103.1668 * Math.exp(-0.04354 * loss) - 3.1669,0,100);
  function gameAccuracy(moves) {
    if (!moves.length) return null;
    const weighted = moves.reduce((s,m) => s+m.accuracy*m.weight,0) / moves.reduce((s,m) => s+m.weight,0);
    const harmonic = moves.some(m => m.accuracy === 0) ? 0 : moves.length / moves.reduce((s,m) => s+1/m.accuracy,0);
    return clamp((weighted+harmonic)/2,0,100);
  }
  function position(initialFEN, history) {
    if (!Array.isArray(history) || history.length > 600) throw Error('棋谱长度无效');
    const board = new Chess(initialFEN);
    for (const code of history) {
      if (board.isGameOver()) throw Error('棋谱在终局后仍有走子');
      board.move(moveObject(code));
    }
    return board;
  }
  function terminal(board) {
    if (board.isCheckmate()) {
      const winner = board.turn() === 'w' ? 'b' : 'w';
      return {cp:winner==='w'?10000:-10000,win:winner==='w'?100:0,mate:0,winner,depth:0,terminal:true,draw:false,pv:[],best:null,nodes:0};
    }
    if (board.isDraw()) return {cp:0,win:50,depth:0,terminal:true,draw:true,pv:[],best:null,nodes:0};
    return null;
  }
  function normalize(answer, board) {
    if (!answer.score || !['cp','mate'].includes(answer.score.type) || !Number.isFinite(answer.score.value) || !Number.isInteger(answer.depth) || answer.depth < 1) throw Error('引擎未完成有效评分');
    const value = answer.score.value * (board.turn()==='w'?1:-1);
    const base = {depth:answer.depth,best:answer.move,pv:answer.pv||[],nodes:answer.nodes||0,terminal:false,draw:false};
    if (answer.score.type === 'mate') {
      const winner = answer.score.value === 0 ? (board.turn()==='w'?'b':'w') : (value>0?'w':'b');
      return {...base,cp:winner==='w'?10000:-10000,win:winner==='w'?100:0,mate:Math.abs(value),winner};
    }
    return {...base,cp:value,win:winPercent(value)};
  }
  function material(board, color) {
    return board.board().flat().filter(Boolean).reduce((s,p) => s+(p.color===color?1:-1)*values[p.type],0);
  }
  function lineFacts(fen, codes, color) {
    const board = new Chess(fen), start = material(board,color), steps = [];
    for (const code of codes) {
      if (board.isGameOver()) throw Error('变化线越过终局');
      const m = board.move(moveObject(code));
      steps.push({code,san:m.san,color:m.color,piece:m.piece,from:m.from,to:m.to,captured:m.captured||'',captureSquare:m.isEnPassant()?m.to[0]+m.from[1]:m.to,promotion:m.promotion||'',check:board.inCheck(),mate:board.isCheckmate(),stalemate:board.isStalemate(),castle:m.isKingsideCastle()||m.isQueensideCastle()});
    }
    return {steps,delta:material(board,color)-start,mate:board.isCheckmate(),winner:board.isCheckmate()?(board.turn()==='w'?'b':'w'):null};
  }
  function coach(fen, played, bestPV, playedPV) {
    const before = new Chess(fen), color = before.turn();
    const actual = lineFacts(fen,playedPV,color), recommended = lineFacts(fen,bestPV,color);
    if (actual.steps[0]?.code !== played || !recommended.steps.length) throw Error('讲解变化线与走法不符');
    const first = actual.steps[0], better = recommended.steps[0];
    const same = better.code === played;
    let why = '', missed = '', theme = '比较变化';
    if (first.mate) {
      why = `${first.san} 已经将死：对方王被将军，且没有任何合法应将。`;
      missed = same ? '你已经结束棋局，没有漏掉应将。' : '本次首选是另一种将死走法；你的走法同样直接将死，不是漏杀。';
      theme = '完成将死';
    } else if (same) {
      why = '你走出了本次引擎首选。下面的变化展示对方可能的应手。';
      if (better.mate) why = `${better.san} 直接将死：对方被将军且没有任何合法应将。`;
      else if (better.check) why += ` ${better.san} 先将军，对方下一手必须解除将军。`;
      else if (better.captured) why += ` 这一步吃掉对方的${pieceNames[better.captured]}；把后续回吃一起算进去再判断收益。`;
      else if (better.piece==='p' && ['d4','e4','d5','e5'].includes(better.to)) why += ` 兵推进到中心 ${better.to}，争夺中心空间；接着要看对方如何挑战这颗兵。`;
      else if (['n','b'].includes(better.piece) && better.from[1] === (color==='w'?'1':'8')) why += ` ${pieceNames[better.piece]}从底线 ${better.from} 出动到 ${better.to}，开始参与后续作战。`;
      missed = '本次搜索没有找到比这步更好的首选；搜索仍可能遗漏更深变化。'; theme = '找到首选';
    } else if (better.mate) {
      why = `${better.san} 直接将死：对方王被将军，且没有任何合法应将。`;
      missed = first.stalemate ? '实际走法让对方无棋可走，但王没有被将军，因此是逼和；推荐着能一步将死。' : '实际走法没有立即将死，你漏掉了一步将死。'; theme = '一步将死';
    } else {
      const reply = actual.steps[1];
      if (reply?.mate) {
        missed = `走 ${first.san} 后，对方可以 ${reply.san} 直接将死。`; theme = '防住将死';
      } else if (reply?.captured) {
        missed = `实际走 ${first.san} 后，这条变化里对方用 ${reply.san} 吃掉你在 ${reply.captureSquare} 的${pieceNames[reply.captured]}。`;
        missed += actual.delta < 0 ? `算上这条线中的后续交换，你比落子前少了约 ${-actual.delta} 兵的子力。` : '这不等于净亏子：还要看后续回吃；已展示的变化没有净子力损失。';
        theme = '先看对方应手';
      } else if (first.stalemate) {
        missed = '实际走法形成逼和：对方没有合法着，但王没有被将军，棋局因此和棋。'; theme = '分清逼和与将死';
      } else {
        missed = `你走了 ${first.san}；对方在参考变化中${reply ? `选择 ${reply.san}` : '尚无后续应手'}。比较两条线，而不只看第一步。`;
      }
      if (better.castle) why = `${better.san} 同时完成王车易位，把王移到 ${better.to}，并让车离开角落参与后续活动。是否安全仍要检查对方的将军。`;
      else if (better.promotion) why = `${better.san} 把兵升变为${pieceNames[better.promotion]}，直接改变可用子力与走法。`;
      else if (better.check) why = `${better.san} 先将军，对方必须应将；参考线接着展示${recommended.steps[1] ? ` ${recommended.steps[1].san} 的应对` : '后续局面'}。`;
      else if (better.captured) why = `${better.san} 先吃掉对方的${pieceNames[better.captured]}。${recommended.delta>0 ? `这条变化结束时，子力账面比落子前净多约 ${recommended.delta} 兵；更远的回吃仍要继续算。` : '但吃子不代表净赚，要连同对方回吃一起看。'}`;
      else if (['n','b'].includes(better.piece) && better.from[1] === (color==='w'?'1':'8') && better.to[1] !== better.from[1]) why = `${better.san} 把${pieceNames[better.piece]}从底线 ${better.from} 出动到 ${better.to}，让它参与中盘，而不是继续留在原位。具体作用要结合参考应手判断。`;
      else {
        const bestBoard = new Chess(fen); bestBoard.move(moveObject(better.code));
        const actualBoard = new Chess(fen); actualBoard.move(moveObject(played));
        const extra = ['d4','e4','d5','e5'].filter(s => bestBoard.isAttacked(s,color) && !actualBoard.isAttacked(s,color));
        why = extra.length ? `${better.san} 后，你对中心 ${extra.join('、')} 的攻击覆盖比实际走法多；这是一项可核对的区别，不单凭它断定好坏。` : `${better.san} 是本次搜索首选。当前没有足够证据把优势概括为具体战术；请回放两条线观察对方应手，不把分数差编成战略理由。`;
      }
      if (recommended.mate && !better.mate) why += ' 这条参考线以将死结束；仅验证一条线不代表穷尽了所有防守。';
    }
    return {theme,summary:`${color==='w'?'白':'黑'}方 ${first.san}${same?' · 本次首选':` → 可比较 ${better.san}`}`,why,missed,habit:'落子前依次检查：对方有哪些将军、吃子和直接威胁？',boundary:'讲解来自棋规与引擎变化，不是大模型。参考线是合法示例；浅层或限时搜索可能漏算。',bestSAN:recommended.steps.map(s=>s.san),playedSAN:actual.steps.map(s=>s.san)};
  }
  function build(input, evaluations) {
    if (input.engine !== engine || input.metric !== metric) throw Error('分析引擎或准确度口径不匹配');
    const board = position(input.initialFEN,[]), record = [];
    for (const code of input.history) { if(board.isGameOver())throw Error('终局后仍有走子'); record.push(board.move(moveObject(code))); }
    if (evaluations.length !== record.length+1) throw Error('分析尚未覆盖全部局面');
    evaluations.forEach(e => { if(!Number.isFinite(e.win)||e.win<0||e.win>100||!Number.isFinite(e.cp)||!Number.isInteger(e.depth)||(!e.terminal&&e.depth<1))throw Error('存在未完成的局面评分'); });
    const entries = record.map((move,i) => {
      const before = evaluations[i], after = evaluations[i+1], white = move.color==='w';
      const beforeWin = white?before.win:100-before.win, afterWin = white?after.win:100-after.win;
      const rawLoss = Math.max(0,beforeWin-afterWin), best = before.best===codeOf(move), forced = before.legalCount===1;
      const loss = best||forced?0:rawLoss;
      const window = evaluations.slice(Math.max(0,i-2),Math.min(evaluations.length,i+3)).map(e=>e.win), average = mean(window);
      const weight = clamp(Math.sqrt(mean(window.map(x=>(x-average)**2))),1,12);
      const legalPV = (prefix,pv,limit) => {
        const b = position(input.initialFEN,prefix), line = [];
        for (const code of pv.slice(0,limit)) { if(b.isGameOver())break; b.move(moveObject(code)); line.push(code); }
        return line;
      };
      const bestPV = legalPV(input.history.slice(0,i),before.pv,12), playedPV = [codeOf(move),...legalPV(input.history.slice(0,i+1),after.pv,11)];
      if (bestPV[0] !== before.best) throw Error('首选与变化线不一致');
      const explanation = coach(move.before,codeOf(move),bestPV,playedPV);
      return {ply:i+1,color:move.color,san:move.san,number:Number(move.before.split(' ')[5]),loss,rawLoss,accuracy:moveAccuracy(loss),weight,forced,
        category:best||forced?'best':loss>=20?'blunder':loss>=10?'mistake':loss>=5?'inaccuracy':loss<1?'excellent':'good',
        bestPV,playedPV,coach:explanation};
    });
    const depths = evaluations.filter(e=>!e.terminal).map(e=>e.depth);
    return {metric,engine,initialFEN:input.initialFEN,history:input.history,duration:input.duration,gameComplete:input.gameComplete||board.isGameOver(),
      evaluations,entries,white:gameAccuracy(entries.filter(m=>m.color==='w')),black:gameAccuracy(entries.filter(m=>m.color==='b')),
      minDepth:depths.length?Math.min(...depths):0,maxDepth:depths.length?Math.max(...depths):0};
  }
  return {metric,engine,position,terminal,normalize,build,coach,winPercent,moveAccuracy,gameAccuracy};
})();
