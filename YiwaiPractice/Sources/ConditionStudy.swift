import Foundation
import Combine

struct ConditionAnswer:Codable {
    let submissionID:UUID; let choice:String; let submittedAt:Date
    let candidates:String; let threat:String; let correct:Bool
}
struct ConditionTrial:Codable,Identifiable {
    let id:UUID; let submissionID:UUID; let position:ConditionPosition
    var shownAt:Date?; var firstAnswer:ConditionAnswer?; var exclusions:[String]=[]
    var candidates=""; var threat=""
}
struct ConditionRetry:Codable,Identifiable {
    let id:UUID; let trialID:UUID; let answer:ConditionAnswer
    let exclusion:String // Separate attempt after feedback; never replaces firstAnswer.
}
struct ConditionRecall:Codable,Identifiable { let id:UUID; let trialID:UUID; let text:String; let at:Date; let origin:String }
struct ConditionPause:Codable { let at:Date; let action:String }
struct ConditionRun:Codable,Identifiable {
    let id:UUID; let phase:String; let sourceRunID:UUID?; let seed:String; let counterbalanceCell:Int
    let startedAt:Date; let demonstration:Bool
    var trials:[ConditionTrial]; var feedbackAt:Date?; var transferDueAt:Date?
    var paused=false; var pauses:[ConditionPause]=[]; var retries:[ConditionRetry]=[]; var recalls:[ConditionRecall]=[]
    var current:ConditionTrial? { trials.first{$0.firstAnswer==nil} }
    var completedCount:Int { trials.filter{$0.firstAnswer != nil}.count }
}
struct ConditionExposure:Codable {
    let key:String; let positionID:String; let version:Int; let family:String
    let runID:UUID; let at:Date; let source:String
}
struct ConditionArchive:Codable {
    var schemaVersion=1
    var clockOrigin:String?="device clock"
    var runs:[ConditionRun]=[]
    var exposures:[ConditionExposure]=[]
    var catalog:ConditionCatalog?
    var engineChecks:[ConditionEngineCheck]?
}
private struct StudyRandom {
    var value:UInt64
    mutating func next() -> UInt64 {
        value &+= 0x9E3779B97F4A7C15
        var z=value;z=(z^(z>>30)) &* 0xBF58476D1CE4E5B9;z=(z^(z>>27)) &* 0x94D049BB133111EB
        return z^(z>>31)
    }
    mutating func shuffle<T>(_ a:[T]) -> [T] {
        var out=a
        if out.count>1 { for i in stride(from:out.count-1,through:1,by:-1) { out.swapAt(i,Int(next()%UInt64(i+1))) } }
        return out
    }
}
enum ConditionOrder {
    static func make(_ positions:[ConditionPosition], seed:UInt64, phase:String) -> [ConditionPosition] {
        var rng=StudyRandom(value:seed)
        if phase=="transfer" { return rng.shuffle(positions) }
        let families=rng.shuffle(Array(Set(positions.map(\.family))).sorted())
        let rows=[["A","B","D","C"],["B","C","A","D"],["C","D","B","A"],["D","A","C","B"]]
        var result:[ConditionPosition]=[]
        for round in 0..<4 {
            // Every round interleaves all families; rotate family order rather than clustering a family.
            for offset in 0..<families.count {
                let index=(offset+round)%families.count, family=families[index]
                let condition=rows[(Int(seed%4)+index)%4][round]
                if let p=positions.first(where:{$0.family==family && $0.condition==condition}) { result.append(p) }
            }
        }
        return result
    }
}
struct ConditionSummary {
    let message:String; let contrary:[String]; let eligibleFamilies:Int
    static func evaluate(_ run:ConditionRun) -> Self {
        guard run.feedbackAt != nil, run.phase=="comparison" else { return .init(message:"这些记录只说明你提交了什么，不能完整反映你当时看到了什么。",contrary:[],eligibleFamilies:0) }
        let families=Array(Set(run.trials.map{$0.position.family})).sorted()
        var eligible=0, capturePatterns:[String]=[], defensePatterns:[String]=[], contrary:[String]=[]
        for family in families {
            let trials=run.trials.filter{$0.position.family==family}
            guard trials.count==4, Set(trials.map{$0.position.condition})==Set(["A","B","C","D"]), trials.allSatisfy({$0.firstAnswer != nil && $0.exclusions.isEmpty}), !run.demonstration else {
                contrary.append("\(family)：有未提交、已见、示例或反馈后记录，不能纳入条件比较");continue
            }
            eligible += 1
            let a=trials.first{$0.position.condition=="A"}!, b=trials.first{$0.position.condition=="B"}!, c=trials.first{$0.position.condition=="C"}!, d=trials.first{$0.position.condition=="D"}!
            let capture=a.firstAnswer!.correct && c.firstAnswer!.correct && b.firstAnswer!.choice==b.position.distractingCapture && d.firstAnswer!.choice==d.position.distractingCapture
            let defense=a.firstAnswer!.correct && b.firstAnswer!.correct && c.firstAnswer!.choice==c.position.critical && d.firstAnswer!.choice==d.position.critical
            if capture { capturePatterns.append(family) } else { contrary.append("\(family)：没有出现‘有指定吃子机会时两次都选了该吃子着’这一完整模式") }
            if defense { defensePatterns.append(family) } else { contrary.append("\(family)：没有出现‘防守改变后两次仍沿用原将死着’这一完整模式") }
        }
        let message:String
        if eligible==3 && capturePatterns.count==3 {
            message="三组完整首答都出现：有指定吃子机会时提交了该吃子着，其余两个条件核对正确。可尝试先检查将军后的全部合法应对。这只是暂定练习提示，不证明你当时被什么吸引。"
        } else if eligible==3 && defensePatterns.count==3 {
            message="三组完整首答都出现：原防守条件下答对，防守改变后仍提交原着。可尝试每次重新核对能吃子、挡将或移王的防守。这只是暂定练习提示，不证明某种心理盲区。"
        } else {
            message="尚无三组完整且一致的首答模式，暂不给条件倾向提示。未提交不算错误，答对也不等于已经稳定掌握。"
        }
        return .init(message:message,contrary:contrary,eligibleFamilies:eligible)
    }
}
@MainActor final class ConditionStudyStore:ObservableObject {
    @Published private(set) var data=ConditionArchive()
    @Published private(set) var positions:[ConditionPosition]=[]
    @Published private(set) var issues:[String]=[]
    @Published private(set) var preparing=false
    @Published private(set) var loadError:String?
    private let file:URL
    private let clock:()->Date
    private var readable=true
    private var prepared=false
    var now:Date { clock() }
    var activeRun:ConditionRun? { data.runs.last{$0.feedbackAt==nil} }
    init(file:URL?=nil,clock:@escaping ()->Date=Date.init,clockOrigin:String="device clock") {
        self.file=file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/conditions-v1.json")
        self.clock=clock
        data.clockOrigin=clockOrigin
        do {
            if FileManager.default.fileExists(atPath:self.file.path) {
                data=try JSONDecoder().decode(ConditionArchive.self,from:Data(contentsOf:self.file))
                guard data.schemaVersion==1 else { throw ChessFailure.invalid("不支持的对照记录版本") }
            }
        } catch { readable=false;loadError="对照记录暂不能读取，原文件保留。\(error.localizedDescription)" }
    }
    func prepare() async {
        guard !prepared, !preparing else { return };preparing=true
        let result=await Task.detached(priority:.userInitiated) { () -> Result<(ConditionCatalog,[ConditionEngineCheck],[ConditionPosition],[String]),Error> in
            Result {
                let catalog=try ConditionCatalog.bundled(), checks=try ConditionCatalog.engineChecks()
                let checked=try ConditionRules().available(catalog,checks:checks)
                return (catalog,checks,checked.positions,checked.issues)
            }
        }.value
        preparing=false;prepared=true
        switch result {
        case .success(let (catalog,checks,valid,errors)):data.catalog=catalog;data.engineChecks=checks;positions=valid;issues=errors
        case .failure(let error):issues=[error.localizedDescription]
        }
    }
    func run(_ id:UUID) -> ConditionRun? { data.runs.first{$0.id==id} }
    func start(seed:UInt64,demonstration:Bool=false) throws -> UUID {
        if let activeRun { return activeRun.id }
        let group=positions.filter{$0.family != "transfer"}
        guard group.count==12, Set(group.map(\.family)).count==3 else { throw ChessFailure.invalid("完整三组尚未通过全部验证，暂不开放实验。") }
        return try create(group,seed:seed,phase:"comparison",source:nil,demonstration:demonstration)
    }
    func startTransfer(sourceID:UUID,seed:UInt64,known:Set<String>) throws -> UUID {
        if let existing=data.runs.first(where:{$0.sourceRunID==sourceID && $0.phase=="transfer"}) { return existing.id }
        guard activeRun==nil, let source=run(sourceID), source.phase=="comparison", let due=source.transferDueAt, now>=due else { throw ChessFailure.invalid("请先完成本轮，按实际结束时间等待 24 小时后再来。") }
        let group=positions.filter{$0.family=="transfer"}, seen=Set(data.exposures.map(\.key)).union(known)
        guard group.count==4, group.allSatisfy({!seen.contains(ReforgeRules.key($0.fen))}) else { throw ChessFailure.invalid("待准备：没有四个符合本机未见条件的已验证延时局面，不会把旧题改名重用。") }
        return try create(group,seed:seed,phase:"transfer",source:source,demonstration:source.demonstration)
    }
    private func create(_ group:[ConditionPosition],seed:UInt64,phase:String,source:ConditionRun?,demonstration:Bool) throws -> UUID {
        let ordered=ConditionOrder.make(group,seed:seed,phase:phase)
        let trials=ordered.map { ConditionTrial(id:UUID(),submissionID:UUID(),position:$0) }
        let run=ConditionRun(id:UUID(),phase:phase,sourceRunID:source?.id,seed:String(seed),counterbalanceCell:Int(seed%4),startedAt:now,demonstration:demonstration,trials:trials)
        var next=data;next.runs.append(run);try save(next);return run.id
    }
    @discardableResult func present(runID:UUID,known:Set<String>,expose:(ReforgeSeen)throws->Void) throws -> ConditionTrial? {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}), data.runs[i].feedbackAt==nil,
              let t=data.runs[i].trials.firstIndex(where:{$0.firstAnswer==nil}) else { return nil }
        try verifySnapshot(data.runs[i].trials[t].position)
        if data.runs[i].trials[t].shownAt != nil { return data.runs[i].trials[t] }
        var next=data, trial=next.runs[i].trials[t]
        let key=ReforgeRules.key(trial.position.fen)
        if known.contains(key) || data.exposures.contains(where:{$0.key==key}) { trial.exclusions.append("本机已记录或已展示的局面") }
        if data.runs[i].demonstration { trial.exclusions.append("示例记录，不计独立比较") }
        if data.exposures.contains(where:{$0.family==trial.position.family && $0.source=="feedback"}) { trial.exclusions.append("已看过本组相关反馈") }
        if let sourceID=data.runs[i].sourceRunID, let source=run(sourceID), source.completedCount != source.trials.count { trial.exclusions.append("来源练习未完整提交") }
        trial.shownAt=now;next.runs[i].trials[t]=trial
        let exposure=ConditionExposure(key:key,positionID:trial.position.id,version:trial.position.version,family:trial.position.family,runID:runID,at:now,source:data.runs[i].demonstration ? "demo":"first-display")
        try expose(.init(key:key,puzzleID:trial.position.id,version:trial.position.version,at:now,source:"condition-\(exposure.source)"))
        next.exposures.append(exposure);try save(next);return trial
    }
    func draft(runID:UUID,trialID:UUID,candidates:String,threat:String) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}), let t=data.runs[i].trials.firstIndex(where:{$0.id==trialID}),data.runs[i].trials[t].firstAnswer==nil,data.runs[i].feedbackAt==nil,!data.runs[i].paused else { return }
        guard candidates.count<=1000,threat.count<=1000 else { throw ChessFailure.invalid("可选记录每项最多 1,000 字。") }
        if data.runs[i].trials[t].candidates==candidates && data.runs[i].trials[t].threat==threat { return }
        var next=data;next.runs[i].trials[t].candidates=candidates;next.runs[i].trials[t].threat=threat;try save(next)
    }
    func pause(_ id:UUID,resume:Bool=false) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==id}),data.runs[i].feedbackAt==nil else { return }
        guard data.runs[i].paused==resume else { return }
        var next=data;next.runs[i].paused = !resume;next.runs[i].pauses.append(.init(at:now,action:resume ? "resume":"pause"));try save(next)
    }
    func submit(runID:UUID,trialID:UUID,submissionID:UUID,choice:String) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}), let t=data.runs[i].trials.firstIndex(where:{$0.id==trialID}) else { throw ChessFailure.invalid("记录不存在。") }
        let trial=data.runs[i].trials[t]
        if let previous=trial.firstAnswer {
            guard previous.submissionID==submissionID && previous.choice==choice else { throw ChessFailure.invalid("首次答案已保留，反馈后的重试另行记录。") };return
        }
        guard data.runs[i].feedbackAt==nil,!data.runs[i].paused,trial.submissionID==submissionID,
              let shown=trial.shownAt,now>=shown else { throw ChessFailure.invalid("请恢复本题后提交；设备时间不能早于展示时间。") }
        try validateChoice(choice,position:trial.position)
        let answer=ConditionAnswer(submissionID:submissionID,choice:choice,submittedAt:now,candidates:trial.candidates,threat:trial.threat,correct:choice=="none" ? trial.position.answers.isEmpty : trial.position.answers.contains(choice))
        var next=data;next.runs[i].trials[t].firstAnswer=answer;try save(next)
    }
    /// Called only after all first answers or explicit end-and-review confirmation. Persists before feedback UI.
    func finish(_ id:UUID,expose:(ReforgeSeen)throws->Void) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==id}) else { throw ChessFailure.invalid("记录不存在。") }
        if data.runs[i].feedbackAt != nil { return }
        guard now>=data.runs[i].startedAt else { throw ChessFailure.invalid("设备时间早于本轮开始，未展示反馈。") }
        for trial in data.runs[i].trials { try verifySnapshot(trial.position) }
        var next=data;next.runs[i].feedbackAt=now;next.runs[i].paused=false
        if next.runs[i].phase=="comparison" { next.runs[i].transferDueAt=now.addingTimeInterval(86400) }
        for trial in next.runs[i].trials {
            let p=trial.position,key=ReforgeRules.key(p.fen)
            try expose(.init(key:key,puzzleID:p.id,version:p.version,at:now,source:"condition-feedback"))
            next.exposures.append(.init(key:key,positionID:p.id,version:p.version,family:p.family,runID:id,at:now,source:"feedback"))
        }
        try save(next)
    }
    func retry(runID:UUID,trialID:UUID,choice:String) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}),data.runs[i].feedbackAt != nil,
              let trial=data.runs[i].trials.first(where:{$0.id==trialID}) else { throw ChessFailure.invalid("重试只在本轮反馈后单独记录。") }
        try validateChoice(choice,position:trial.position)
        let answer=ConditionAnswer(submissionID:UUID(),choice:choice,submittedAt:now,candidates:"",threat:"",correct:choice=="none" ? trial.position.answers.isEmpty : trial.position.answers.contains(choice))
        var next=data;next.runs[i].retries.append(.init(id:UUID(),trialID:trialID,answer:answer,exclusion:"看过反馈后的重试，排除首次比较"));try save(next)
    }
    private func verifySnapshot(_ position:ConditionPosition) throws {
        guard positions.contains(where:{$0.digest==position.digest}) else { throw ChessFailure.invalid("这版题目尚未通过完整验证，原记录保留。") }
    }
    private func validateChoice(_ choice:String,position:ConditionPosition) throws {
        try verifySnapshot(position)
        if choice=="none" { return }
        guard try ChessEngine().frames(fen:position.fen)[0].replies.contains(where:{$0.code==choice}) else { throw ChessFailure.invalid("请选择一个合法走法，或选择没有一步将死。") }
    }
    func markAssisted(runID:UUID,trialID:UUID) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}), let t=data.runs[i].trials.firstIndex(where:{$0.id==trialID}),data.runs[i].trials[t].firstAnswer==nil,data.runs[i].feedbackAt==nil,!data.runs[i].paused else { return }
        let reason="用户标记已见或参考了外部提示"
        guard !data.runs[i].trials[t].exclusions.contains(reason) else { return }
        var next=data;next.runs[i].trials[t].exclusions.append(reason);try save(next)
    }
    func recall(runID:UUID,trialID:UUID,text:String) throws {
        guard let i=data.runs.firstIndex(where:{$0.id==runID}),data.runs[i].feedbackAt != nil,
              data.runs[i].trials.contains(where:{$0.id==trialID}), !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.count<=2000 else { throw ChessFailure.invalid("请在反馈后填写补记，最多 2,000 字。") }
        var next=data;next.runs[i].recalls.append(.init(id:UUID(),trialID:trialID,text:text,at:now,origin:"after-feedback; excluded from first-answer comparison"));try save(next)
    }
    func exportArchive() throws -> ConditionArchive {
        guard readable else { throw ChessFailure.invalid("原对照记录不可读取，不能完整导出。") }
        guard activeRun==nil else { throw ChessFailure.invalid("完整对照导出含题目答案；请先在对照练习中选择结束并查看，避免提前暴露反馈。") }
        return data
    }
    private func save(_ next:ConditionArchive) throws {
        guard readable else { throw ChessFailure.invalid("原文件读取失败，未覆盖。") }
        do { try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(next).write(to:file,options:.atomic);data=next }
        catch { throw ChessFailure.invalid("未能保存对照记录，没有确认提交；请检查本机空间。") }
    }
}
