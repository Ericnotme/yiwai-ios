// Shared by the web client and iOS JavaScriptCore. No network or storage.
globalThis.YiwaiImport = (() => {
  function fail(message) { throw new Error(message); }
  function fen(text, Chess) {
    if (typeof text !== 'string' || !text.trim()) fail('请先粘贴 FEN 局面。');
    if (text.length > 512) fail('FEN 最多 512 个字符。');
    const p = text.trim().split(/\s+/);
    if (p.length !== 6) fail('FEN 需要六个字段：棋盘、走棋方、易位、过路兵、半回合、回合数。');
    if (!/^[wb]$/.test(p[1])) fail('走棋方必须为 w（白）或 b（黑）。');
    if (!/^(?:-|K?Q?k?q?)$/.test(p[2]) || !p[2]) fail('易位字段应为 - 或按 KQkq 顺序列出的权限。');
    if (!/^(?:-|[a-h][36])$/.test(p[3])) fail('过路兵目标应为 - 或第三／第六横线的格子。');
    if (!/^\d+$/.test(p[4]) || !Number.isSafeInteger(+p[4]) || +p[4] > 1000000) fail('半回合计数必须为 0–1000000 的整数。');
    if (!/^[1-9]\d*$/.test(p[5]) || !Number.isSafeInteger(+p[5]) || +p[5] > 1000000) fail('完整回合数必须为 1–1000000 的整数。');
    p[4] = String(+p[4]); p[5] = String(+p[5]);
    let b;
    try { b = new Chess(p.join(' ')); } catch { fail('棋盘字段无效：检查八行八列、双方各一王，以及兵不在底线。'); }
    const pieces = b.board().flat().filter(Boolean);
    for (const color of ['w','b']) if (pieces.filter(p=>p.color===color).length>16 || pieces.filter(p=>p.color===color&&p.type==='p').length>8) fail('每方最多十六个棋子、八个兵。');
    const is = (square, type, color) => b.get(square)?.type === type && b.get(square)?.color === color;
    for (const [right, king, rook, color] of [['K','e1','h1','w'],['Q','e1','a1','w'],['k','e8','h8','b'],['q','e8','a8','b']]) {
      if (p[2].includes(right) && (!is(king,'k',color) || !is(rook,'r',color))) fail('易位权限与王、车的位置不符。');
    }
    if (p[3] !== '-') {
      const white = p[1] === 'w', file = p[3][0];
      if (p[3][1] !== (white ? '6' : '3') || b.get(p[3]) || !is(file+(white?'5':'4'),'p',white?'b':'w') || b.get(file+(white?'7':'2')) || +p[4] !== 0 || white && +p[5] < 2) fail('过路兵字段与轮次、刚走两格的兵或半回合计数不符。');
      // FEN may name the target even when no opposing pawn can capture it.
    }
    const other = [...p]; other[1] = p[1] === 'w' ? 'b' : 'w'; other[3] = '-';
    if (new Chess(other.join(' ')).isCheck()) fail('局面不合法：刚走棋一方的王仍被攻击，或两王相邻。');
    return p.join(' ');
  }
  function parse(text, format, Chess) {
    if (format === 'fen') {
      const initialFen = fen(text, Chess), b = new Chess(initialFen);
      b.setHeader('SetUp','1'); b.setHeader('FEN',initialFen);
      return {initialFen,moves:[],headers:b.getHeaders()};
    }
    if (format !== 'pgn') fail('请选择 FEN 或 PGN。');
    if (typeof text !== 'string' || !text.trim()) fail('请先粘贴 PGN 棋谱。');
    if (text.length > 200000) fail('请导入单盘棋谱（最多 200 KB）。');
    let b;
    try { b = new Chess(); b.loadPgn(text); } catch { fail('无法读取这份棋谱。请检查 PGN 格式和走法。'); }
    const history = b.history({verbose:true}), headers = b.getHeaders();
    // chess.js removes SetUp/FEN when loading the ordinary starting position.
    const headerBlock = text.match(/^\s*(?:\[[^\r\n]*\]\s*)+/)?.[0] || '';
    const supplied = [...headerBlock.matchAll(/\[FEN\s+"([^"]*)"\]/g)];
    if (!headers.FEN && supplied.length === 1 && fen(supplied[0][1],Chess) === new Chess().fen()) { headers.FEN = new Chess().fen(); headers.SetUp = '1'; }
    if (!history.length && !headers.FEN) fail('棋谱中没有走子记录或 FEN 局面。');
    const initialFen = fen(headers.FEN || history[0].before, Chess);
    const replay = new Chess(initialFen);
    for (const m of history) {
      if (replay.isGameOver()) fail('棋谱在终局后仍有走子，请检查记录。');
      replay.move({from:m.from,to:m.to,...(m.promotion?{promotion:m.promotion}:{})});
    }
    return {initialFen,moves:history.map(m=>m.from+m.to+(m.promotion||'')),headers};
  }
  return {fen,parse};
})();
