// Local-only worker transport. The unmodified GPL engine remains a separate asset.
window.YiwaiStockfish = (() => {
  let worker, objectURL, pending, readyReject, readyTimer;
  const fail = message => { if(readyReject)readyReject(Error(message)); if(pending){clearTimeout(pending.timer);pending.reject(Error(message));pending=null;} };
  function stop() {
    fail('分析已取消，未完成的局面不会计入准确度');
    clearTimeout(readyTimer);readyReject=null;
    worker?.terminate();worker=null;
    if(objectURL)URL.revokeObjectURL(objectURL);objectURL=null;
  }
  async function initialize(source, wasm) {
    stop();
    objectURL=URL.createObjectURL(new Blob([source],{type:'text/javascript'}));
    // The engine's supported URL hash selects its WASM. A data URL keeps this offline.
    worker=new Worker(objectURL+'#'+encodeURIComponent('data:application/wasm;base64,'+wasm));
    await new Promise((resolve,reject)=>{
      readyReject=reject;
      readyTimer=setTimeout(()=>{fail('本地分析引擎启动超时');stop();},45000);
      worker.onerror=()=>{fail('本地分析引擎未能运行');stop();};
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
          const score=data.match(/score (cp|mate) (-?\d+)/), depth=data.match(/\bdepth (\d+)/), pv=data.match(/\bpv (.+)/), nodes=data.match(/\bnodes (\d+)/);
          if(score&&depth&&pv&&!/\b(lowerbound|upperbound)\b/.test(data))Object.assign(pending,{score:{type:score[1],value:Number(score[2])},depth:Number(depth[1]),pv:pv[1].trim().split(/\s+/),nodes:Number(nodes?.[1]||0)});
        }
        if(pending&&data.startsWith('bestmove ')){
          const p=pending;pending=null;clearTimeout(p.timer);
          p.resolve({move:data.split(' ')[1],score:p.score,depth:p.depth,pv:p.pv||[],nodes:p.nodes||0});
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
