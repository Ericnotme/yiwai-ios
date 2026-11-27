import Foundation
import Combine

@MainActor final class PersonalStore:ObservableObject {
    @Published private(set) var data=PersonalArchive()
    @Published private(set) var error:String?
    let file:URL;private let clock:()->Date
    var now:Date {clock()}
    init(file:URL?=nil,clock:@escaping()->Date=Date.init,clockOrigin:String="device clock") {
        self.file=file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/personal-evidence.json")
        self.clock=clock
        if FileManager.default.fileExists(atPath:self.file.path) {do {data=try JSONDecoder().decode(PersonalArchive.self,from:Data(contentsOf:self.file));guard data.schemaVersion==1 else{throw ChessFailure.invalid("个人证据版本不可读")}}catch{self.error="读取个人证据失败，已停止写入：\(error.localizedDescription)"}}
        data.clockOrigin=clockOrigin
    }
    func item(_ id:UUID)->PersonalCase? {data.cases.first{$0.id==id}}
    func save(_ next:PersonalArchive)throws {
        guard error==nil else{throw ChessFailure.invalid(error!)}
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(next).write(to:file,options:.atomic);data=next
    }
    func update(_ id:UUID,_ mutate:(inout PersonalCase)throws->Void)throws {
        var next=data;guard let i=next.cases.firstIndex(where:{$0.id==id})else{throw ChessFailure.invalid("记录不存在")}
        try mutate(&next.cases[i]);try save(next)
    }
    func add(_ game:GameRecord,side:String,demo:Bool)throws->UUID {
        let key=MatePatternDetector.gameKey(game)
        if let existing=data.cases.first(where:{$0.gameKey==key && $0.side==side && $0.demonstration==demo}){return existing.id}
        var next=data;let value=PersonalCase(game:game,gameKey:key,side:side,demonstration:demo,createdAt:now);next.cases.append(value);try save(next);return value.id
    }
    static func round(_ positions:[PersonalPosition],kind:String,at:Date,demo:Bool)->PersonalRound {
        let seed=UInt64.random(in:1...UInt64.max)
        let ordered=seed%2==0 ? positions:Array(positions.reversed())
        return PersonalRound(id:UUID(),kind:kind,seed:seed,startedAt:at,trials:ordered.map{PersonalTrial(id:UUID(),submissionID:UUID(),position:$0,kind:kind,exclusions:(demo ? ["demonstration"]:[])+(kind=="review" ? ["retrospective original/related branch"]:[]))})
    }
    func present(_ id:UUID,known:Set<String>,expose:(ReforgeSeen)throws->Void)throws {
        guard let round=item(id)?.active,let trial=round.current,trial.shownAt==nil else{return}
        let proof=try PersonalRules().validate(history:trial.position.history)
        guard ReforgeRules.key(proof.fen)==ReforgeRules.key(trial.position.fen),proof.answers==trial.position.answers.sorted(),trial.position.version>0 else{throw ChessFailure.invalid("保存的题目证明不完整，暂不展示")}
        let at=now,seen=known.contains(where:{PersonalRules.near(trial.position.fen,$0)})
        try expose(.init(key:ReforgeRules.key(trial.position.fen),puzzleID:trial.position.id,version:trial.position.version,at:at,source:"personal-\(round.kind)"))
        try update(id) {c in
            let r=c.rounds.firstIndex{$0.id==round.id}!,t=c.rounds[r].trials.firstIndex{$0.id==trial.id}!
            c.rounds[r].trials[t].shownAt=at
            if seen && round.kind != "review" {c.rounds[r].trials[t].exclusions.append("locally seen or near duplicate")}
        }
    }
    func draft(_ id:UUID,candidates:String,reason:String)throws {
        guard candidates.count<=1000,reason.count<=4000 else{throw ChessFailure.invalid("候选着最多 1,000 字，理由最多 4,000 字")}
        try update(id){c in guard let r=c.rounds.lastIndex(where:{$0.feedbackAt==nil}),let t=c.rounds[r].trials.firstIndex(where:{$0.first==nil})else{return};c.rounds[r].trials[t].candidates=candidates;c.rounds[r].trials[t].reason=reason}
    }
    func hint(_ id:UUID)throws {let at=now;try update(id){c in guard let r=c.rounds.lastIndex(where:{$0.feedbackAt==nil}),let t=c.rounds[r].trials.firstIndex(where:{$0.first==nil})else{return};if c.rounds[r].trials[t].hintAt==nil{c.rounds[r].trials[t].hintAt=at};if !c.rounds[r].trials[t].exclusions.contains("hint or self-reported exposure"){c.rounds[r].trials[t].exclusions.append("hint or self-reported exposure")}}}
    func submit(_ id:UUID,trialID:UUID,submissionID:UUID,choice:String)throws {
        let at=now
        try update(id){c in
            guard let r=c.rounds.firstIndex(where:{$0.trials.contains(where:{$0.id==trialID})}),let t=c.rounds[r].trials.firstIndex(where:{$0.id==trialID})else{throw ChessFailure.invalid("题目不存在")}
            let trial=c.rounds[r].trials[t]
            if let first=trial.first {guard first.submissionID==submissionID,first.choice==choice else{throw ChessFailure.invalid("首答已保留，不能覆盖")};return}
            guard c.rounds[r].feedbackAt==nil,c.rounds[r].current?.id==trialID,trial.shownAt != nil,trial.submissionID==submissionID else{throw ChessFailure.invalid("题目已结束或尚未展示")}
            let rules=try PersonalRules(),v=try rules.validate(history:trial.position.history)
            guard v.answers==trial.position.answers.sorted(),choice=="none" || v.legal.contains(choice) else{throw ChessFailure.invalid("请选择合法走法或没有一步将死")}
            c.rounds[r].trials[t].first=PersonalAnswer(submissionID:submissionID,choice:choice,candidates:trial.candidates,reason:trial.reason,at:at,context:trial.kind=="review" ? "retrospective before feedback":"before feedback",exclusions:trial.exclusions)
        }
    }
    func finish(_ id:UUID,expose:(ReforgeSeen)throws->Void)throws {
        guard let round=item(id)?.active else{return};let at=now
        // Write exposure before publishing feedback. A partial failure can only over-exclude.
        for trial in round.trials {try expose(.init(key:ReforgeRules.key(trial.position.fen),puzzleID:trial.position.id,version:trial.position.version,at:at,source:"personal-feedback"))}
        try update(id){c in let r=c.rounds.firstIndex{$0.id==round.id}!;c.rounds[r].feedbackAt=at
            if round.trials.contains(where:{$0.first==nil}) {for t in c.rounds[r].trials.indices{c.rounds[r].trials[t].exclusions.append("round ended incomplete; related feedback exposed")}}
            if round.kind=="practice",round.trials.allSatisfy({$0.first != nil}) {c.dueAt=at.addingTimeInterval(86400)}
        }
    }
    func startCatalog(_ id:UUID,kind:String,known:Set<String>)throws {
        guard let c=item(id),c.active==nil,c.rounds.first?.feedbackAt != nil else{throw ChessFailure.invalid("先完成原局复盘")}
        guard ["practice","transfer"].contains(kind),!c.rounds.contains(where:{$0.kind==kind})else{throw ChessFailure.invalid("本轮已建立；首次记录不会重复创建")}
        if kind=="transfer" {guard let due=c.dueAt,now>=due || (c.demonstration && c.demoTimeAdvancedAt != nil) else{throw ChessFailure.invalid("尚未到期，从实际练习完成时间起等待 24 小时")}}
        let catalog=try ConditionCatalog.bundled(),checks=try ConditionCatalog.engineChecks(),available=try ConditionRules().available(catalog,checks:checks).positions
        let rules=try ChessEngine();var forbidden=known
        for item in data.cases {for f in try rules.frames(fen:item.game.initialFEN,moves:item.game.moves){forbidden.insert(ReforgeRules.key(f.fen))};for t in item.rounds.flatMap(\.trials){forbidden.insert(ReforgeRules.key(t.position.fen))}}
        var pool=available.filter{kind=="practice" ? $0.family != "transfer" : $0.family=="transfer"}.filter{p in !forbidden.contains(where:{PersonalRules.near(p.fen,$0)})}
        var selected:[ConditionPosition]=[]
        for mate in kind=="practice" ? [true]:[true,false] {
            guard let p=pool.first(where:{!$0.answers.isEmpty==mate})else{throw ChessFailure.invalid("已分析，但暂无符合未见及近重复排除要求的可靠匹配题。有限题库不足，不用通用示例冒充个人生成。")}
            selected.append(p);pool.removeAll{PersonalRules.near($0.fen,p.fen)}
        }
        let positions=selected.map{p in PersonalPosition(id:p.id,version:p.version,fen:p.fen,history:p.proofMoves,answers:p.answers,source:"Matched catalog, NOT personal counterfactual. \(catalog.source)\n\(p.pgn)",license:catalog.license,catalogProof:p,catalogCheck:checks.first{$0.id==p.id})}
        let round=Self.round(positions,kind:kind,at:now,demo:c.demonstration);try update(id){$0.rounds.append(round)}
    }
    func recollect(_ id:UUID,text:String,correction:String)throws {
        guard text.count<=4000,correction.count<=1000,item(id)?.rounds.first?.feedbackAt != nil else{throw ChessFailure.invalid("反馈后补记最多 4,000 字，修正最多 1,000 字")}
        let at=now;try update(id){c in c.recollections.append(.init(text:text,at:at,context:"user retrospective after feedback; empty means skipped"));c.hypothesisCorrection=correction}
    }
    func advanceDemo(_ id:UUID)throws {guard let c=item(id),c.demonstration,c.dueAt != nil else{throw ChessFailure.invalid("仅示例可模拟到期")};let at=now;try update(id){$0.demoTimeAdvancedAt=at}}
    func exportArchive()throws->PersonalArchive {guard error==nil else{throw ChessFailure.invalid(error!)};guard !data.cases.contains(where:{$0.active != nil})else{throw ChessFailure.invalid("完整导出含答案，请先结束进行中的个人复盘轮次")};return data}
}

@MainActor final class PersonalPipeline:ObservableObject {
    @Published private(set) var running=false
    @Published private(set) var progress=""
    @Published private(set) var error:String?
    @Published private(set) var engine:StockfishReviewEngine?
    private var task:Task<Void,Never>?;private var cancellation:SearchCancellation?;private var epoch=UUID()
    func cancel(){cancellation?.cancel();task?.cancel();engine?.cancel();engine=nil;epoch=UUID();running=false;progress="已暂停；保留已完成证据，可继续检查"}
    func run(_ id:UUID,store:PersonalStore){
        guard !running,let item=store.item(id),item.rounds.isEmpty,item.status != "complete-no-pair" else{return}
        let token=SearchCancellation(),tag=UUID();epoch=tag;cancellation=token;running=true;error=nil
        task=Task {
            do {
                progress="逐步核对完整主线与所有一步将死着…"
                let scan=try await Task.detached(priority:.userInitiated){try MatePatternDetector(cancellation:token).scan(item.game,side:item.side,at:Date())}.value
                try Task.checkCancellation();guard tag==epoch else{return}
                try store.update(id){$0.scan=scan;$0.status="checking"}
                let rules=try PersonalRules(cancellation:token)
                var found=false
                for evidence in scan.evidence.prefix(3) {
                    try Task.checkCancellation()
                    progress="增加引擎预算，复核候选局面…"
                    let original=try await probes(evidence.history)
                    guard try rules.stable(original,history:evidence.history,answers:evidence.answers)else{try store.update(id){$0.attempts.append(.init(ply:evidence.ply,history:evidence.history,probes:original,outcome:"original unstable; rejected",at:store.now))};continue}
                    try store.update(id){$0.attempts.append(.init(ply:evidence.ply,history:evidence.history,probes:original,outcome:"original stable; complete answer set verified",at:store.now))}
                    let branches=try await Task.detached {try PersonalRules(cancellation:token).branches(evidence)}.value
                    for branch in branches.prefix(2) {
                        progress="复核可重放的合法替代分支…"
                        let alternate=try await probes(branch.history)
                        let stable=try rules.stable(alternate,history:branch.history,answers:[])
                        try Task.checkCancellation();guard tag==epoch else{return}
                        try store.update(id){$0.attempts.append(.init(ply:evidence.ply,history:branch.history,probes:alternate,outcome:stable ? "qualified legal branch":"branch unstable; rejected",at:store.now))}
                        if stable {
                            let source="User supplied standard-start legal mainline; local only. Legal branch changes preceding opponent move; multiple relationships may change, not proof of psychological cause."
                            let pair=[PersonalPosition(id:"\(evidence.id)-original",version:1,fen:evidence.fen,history:evidence.history,answers:evidence.answers,source:source,license:"User-provided PGN; no publication permission implied",probes:original),PersonalPosition(id:"\(evidence.id)-branch",version:1,fen:branch.fen,history:branch.history,answers:[],source:source,license:"Derived local legal branch; no publication",probes:alternate)]
                            let round=PersonalStore.round(pair,kind:"review",at:store.now,demo:item.demonstration)
                            try store.update(id){$0.evidence=evidence;$0.branch=branch;$0.rounds=[round];$0.status="ready"};found=true;break
                        }
                    }
                    if !found {try store.update(id){$0.attempts.append(.init(ply:evidence.ply,history:evidence.history,probes:original,outcome:"No qualified branch among first two legal counterexamples; remaining branches not engine-tested: \(max(0,branches.count-2))",at:store.now))}}
                    if found{break}
                }
                try Task.checkCancellation();guard tag==epoch else{return}
                if !found {try store.update(id){$0.status="complete-no-pair"}}
                progress=found ? "已生成一组可核验局面；请先独立复答":"已分析，但暂无可靠个人原因题。未检测其他错误类型。"
            } catch {
                guard tag==epoch else{return};self.error=error.localizedDescription
                do{try store.update(id){$0.status="paused"}}catch{self.error=error.localizedDescription}
            }
            guard tag==epoch else{return};engine?.cancel();engine=nil;running=false
        }
    }
    private func probes(_ history:[String])async throws->[PersonalProbe] {
        var values:[PersonalProbe]=[]
        for budget in [450,1400] {try Task.checkCancellation();let e=StockfishReviewEngine();engine=e;defer{e.cancel()};values.append(try await e.probe(history:history,duration:budget))}
        return values
    }
}
