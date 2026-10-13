// Local-only worker transport. The unmodified GPL engine remains a separate asset.
// One exact UCI info line is an atomic result. A time-limited bestmove can name
// a newer fail-high (lowerbound) candidate, which has no exact score yet.
var YiwaiUCI = {
  exactResult(line) {
    if (!line.startsWith('info ') || /\b(lowerbound|upperbound)\b/.test(line)) return null;
    const score=line.match(/\bscore (cp|mate) (-?\d+)/), depth=line.match(/\bdepth (\d+)/), pv=line.match(/\bpv (.+)/), nodes=line.match(/\bnodes (\d+)/);
    if (!score || !depth || Number(depth[1]) < 1 || !pv) return null;
    const moves=pv[1].trim().split(/\s+/);
    if (!moves.every(move => /^[a-h][1-8][a-h][1-8][qrbn]?$/.test(move))) return null;
    return {move:moves[0],score:{type:score[1],value:Number(score[2])},depth:Number(depth[1]),pv:moves,nodes:Number(nodes?.[1]||0)};
  }
};
window.YiwaiStockfish = (() => {
  let worker, objectURL, wasmURL, pending, readyReject, readyTimer;
  const fail = message => { if(readyReject)readyReject(Error(message)); if(pending){clearTimeout(pending.timer);pending.reject(Error(message));pending=null;} };
  function stop() {
    fail('分析已取消，未完成的局面不会计入准确度');
    clearTimeout(readyTimer);readyReject=null;
    worker?.terminate();worker=null;
    if(objectURL)URL.revokeObjectURL(objectURL);objectURL=null;
    if(wasmURL)URL.revokeObjectURL(wasmURL);wasmURL=null;
  }
  async function initialize(source, wasm) {
    stop();
    // WebKit rejects URL fragments larger than 2 MiB. The former base64 WASM
    // fragment was 2,552,627 characters, so newer iPhones rejected the worker
    // before any code ran. Keep bytes in a local Blob and pass only its short URL.
    try {
      const bytes=Uint8Array.from(atob(wasm),c=>c.charCodeAt(0));
      wasmURL=URL.createObjectURL(new Blob([bytes],{type:'application/wasm'}));
      objectURL=URL.createObjectURL(new Blob([source],{type:'text/javascript'}));
      worker=new Worker(objectURL+'#'+encodeURIComponent(wasmURL));
    } catch(error) { stop(); throw Error('本地分析资源加载失败，请重试'); }
    await new Promise((resolve,reject)=>{
      readyReject=reject;
      readyTimer=setTimeout(()=>{fail('本地分析引擎启动超时');stop();},45000);
      worker.onerror=()=>{fail(readyReject?'本地分析引擎启动失败（E_WORKER_START）':'本地分析引擎运行中断（E_WORKER_SEARCH）');stop();};
      worker.onmessage=({data})=>{
        if(typeof data!=='string')return;
        if(data==='uciok'){
          worker.postMessage('setoption name Hash value 32');
          worker.postMessage('setoption name Skill Level value 20');
          worker.postMessage('setoption name MultiPV value 1');
          worker.postMessage('isready');
        }
        if(data==='readyok'){clearTimeout(readyTimer);readyReject=null;resolve();}
        if(pending&&data.startsWith('info ')){
          const result=YiwaiUCI.exactResult(data);
          if(result)pending.result=result;
        }
        if(pending&&data.startsWith('bestmove ')){
          const p=pending;pending=null;clearTimeout(p.timer);
          // bestmove ends the search; it must not overwrite the root move of
          // the last exact score/PV. Never treat a bound as a precise score.
          if(p.result)p.resolve(p.result);
          else p.reject(Error('引擎未完成有效评分，请重试'));
        }
      };
      worker.postMessage('uci');
    });
  }
  function search(initialFEN,history,duration){
    if(!worker||pending)throw Error('分析引擎未就绪');
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{fail('本步分析超时，请重试');stop();},duration+12000);
      pending={resolve,reject,timer};
      worker.postMessage('position fen '+initialFEN+(history.length?' moves '+history.join(' '):''));
      worker.postMessage('go movetime '+duration);
    });
  }
  async function run(input,source,wasm){
    if(![450,1400].includes(input.duration))throw Error('分析质量无效');
    const board=YiwaiReview.position(input.initialFEN,input.history); // Validate all moves first.
    void board;
    await initialize(source,wasm);
    try{
      const evaluations=[];
      for(let i=0;i<=input.history.length;i++){
        if(!worker)throw Error('分析已取消');
        const history=input.history.slice(0,i),position=YiwaiReview.position(input.initialFEN,history);
        const value=YiwaiReview.terminal(position)||YiwaiReview.normalize(await search(input.initialFEN,history,input.duration),position);
        if(!worker)throw Error('分析已取消');
        evaluations.push({...value,legalCount:position.moves().length});
        window.webkit.messageHandlers.reviewProgress.postMessage({id:input.runID,completed:i+1,total:input.history.length+1});
      }
      return JSON.stringify(YiwaiReview.build({...input,metric:YiwaiReview.metric,engine:YiwaiReview.engine},evaluations));
    }finally{stop();}
  }
  return {run,stop};
})();
