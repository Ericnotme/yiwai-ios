import XCTest
@testable import YiwaiPractice

final class ConditionStudyTests:XCTestCase {
    private func path()->URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("conditions.json") }
    private let start=Date(timeIntervalSince1970:1792800000)
    @MainActor private func store(_ file:URL?=nil,clock:(()->Date)?=nil) async -> ConditionStudyStore {
        let s=ConditionStudyStore(file:file ?? path(),clock:clock ?? { self.start },clockOrigin:"injected unit test clock; synthetic only")
        await s.prepare();XCTAssertEqual(s.positions.count,16);XCTAssertTrue(s.issues.isEmpty);return s
    }
    @MainActor private func answerAll(_ s:ConditionStudyStore,_ id:UUID,choice:((ConditionPosition)->String)?=nil) throws {
        while let t=try s.present(runID:id,known:[],expose:{_ in}) {
            try s.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:choice?(t.position) ?? t.position.answers.first ?? "none")
        }
    }
    func testAllBundledEvidenceAndFailClosedFamily() throws {
        let c=try ConditionCatalog.bundled(), checks=try ConditionCatalog.engineChecks(), rules=try ConditionRules()
        XCTAssertEqual(rules.available(c,checks:checks).positions.count,16)
        let missing=rules.available(c,checks:checks.filter{$0.id != c.positions[0].id})
        XCTAssertEqual(missing.positions.count,12);XCTAssertEqual(missing.issues.count,1)
        XCTAssertFalse(missing.positions.contains{$0.family==c.positions[0].family})
        let old=checks[0]
        let forged=ConditionEngineCheck(id:old.id,digest:"old",engine:old.engine,checkedAt:old.checkedAt,best:old.best,mate:old.mate,winner:old.winner,depth:old.depth,pv:old.pv)
        XCTAssertThrowsError(try rules.validate(c.positions[0],check:forged))
        let bytes=try JSONEncoder().encode(c.positions[0])
        var obj=try XCTUnwrap(JSONSerialization.jsonObject(with:bytes) as? [String:Any]);obj["pgn"]="1. e5 *"
        let bad=try JSONDecoder().decode(ConditionPosition.self,from:JSONSerialization.data(withJSONObject:obj))
        XCTAssertThrowsError(try rules.validate(bad,requireEngine:false))
    }
    func testSeededInterleavingAndCounterbalance() throws {
        let p=try ConditionCatalog.bundled().positions.filter{$0.family != "transfer"}
        for seed:UInt64 in 0..<12 {
            let order=ConditionOrder.make(p,seed:seed,phase:"comparison")
            XCTAssertEqual(order.map(\.id),ConditionOrder.make(p,seed:seed,phase:"comparison").map(\.id))
            XCTAssertEqual(order.count,12);XCTAssertEqual(Set(order.map(\.id)).count,12)
            for i in stride(from:0,to:12,by:3) { XCTAssertEqual(Set(order[i..<i+3].map(\.family)).count,3) }
            XCTAssertTrue(zip(order,order.dropFirst()).allSatisfy{$0.family != $1.family})
            XCTAssertEqual(Set(order.prefix(3).map(\.condition)).count,3)
        }
        XCTAssertNotEqual(ConditionOrder.make(p,seed:0,phase:"comparison").map(\.id),ConditionOrder.make(p,seed:1,phase:"comparison").map(\.id))
    }
    @MainActor func testFirstAnswerDraftCrashPauseIdempotencyAndRetry() async throws {
        let file=path();defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        var time=start;let s=await store(file,clock:{time}),id=try s.start(seed:47)
        let t=try XCTUnwrap(s.present(runID:id,known:[],expose:{_ in}))
        try s.draft(runID:id,trialID:t.id,candidates:"Q?",threat:"I checked replies")
        try s.pause(id);XCTAssertThrowsError(try s.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:"none"))
        let reopened=await store(file,clock:{time});XCTAssertTrue(reopened.run(id)!.paused)
        XCTAssertEqual(reopened.run(id)!.seed,"47");XCTAssertEqual(reopened.run(id)!.trials.map(\.id),s.run(id)!.trials.map(\.id))
        try reopened.pause(id,resume:true)
        let shown=try XCTUnwrap(reopened.present(runID:id,known:[ReforgeRules.key(t.position.fen)],expose:{_ in XCTFail("Do not expose resumed trial twice") }))
        XCTAssertTrue(shown.exclusions.isEmpty);XCTAssertEqual(shown.candidates,"Q?")
        time=time.addingTimeInterval(21)
        try reopened.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:"none")
        try reopened.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:"none")
        let legal=try ChessEngine().frames(fen:t.position.fen)[0].replies[0].code
        XCTAssertThrowsError(try reopened.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:legal))
        XCTAssertEqual(reopened.run(id)?.completedCount,1);XCTAssertNil(reopened.run(id)?.feedbackAt)
        XCTAssertThrowsError(try reopened.exportArchive())
        try reopened.finish(id,expose:{_ in});try reopened.retry(runID:id,trialID:t.id,choice:legal)
        try reopened.recall(runID:id,trialID:t.id,text:"After feedback only")
        let final=await store(file);let r=try XCTUnwrap(final.run(id))
        XCTAssertEqual(r.trials[0].firstAnswer?.choice,"none");XCTAssertEqual(r.trials[0].firstAnswer?.submittedAt,time)
        XCTAssertEqual(r.trials[0].firstAnswer?.threat,"I checked replies");XCTAssertEqual(r.retries.count,1);XCTAssertEqual(r.recalls.count,1)
        XCTAssertEqual(r.pauses.map(\.action),["pause","resume"])
        XCTAssertEqual(r.trials.filter{$0.firstAnswer==nil}.count,11)
    }
    @MainActor func testFinishExposesAllRemainingAndMissingIsNotWrong() async throws {
        let s=await store(),id=try s.start(seed:0)
        _=try s.present(runID:id,known:[],expose:{_ in})
        var feedback:[ReforgeSeen]=[];try s.finish(id,expose:{feedback.append($0)})
        XCTAssertEqual(feedback.count,12);XCTAssertEqual(s.run(id)!.completedCount,0)
        XCTAssertEqual(ConditionSummary.evaluate(s.run(id)!).eligibleFamilies,0)
        let again=try s.start(seed:0), t=try XCTUnwrap(s.present(runID:again,known:[],expose:{_ in}))
        XCTAssertTrue(t.exclusions.contains("已看过本组相关反馈"));XCTAssertTrue(t.exclusions.contains("本机已记录或已展示的局面"))
    }
    @MainActor func testDemoAssistanceAndSeenAreExcluded() async throws {
        let s=await store(),id=try s.start(seed:2,demonstration:true)
        let p=s.run(id)!.current!.position
        let t=try XCTUnwrap(s.present(runID:id,known:[ReforgeRules.key(p.fen)],expose:{_ in}))
        XCTAssertEqual(t.exclusions.count,2)
        try s.markAssisted(runID:id,trialID:t.id);try s.markAssisted(runID:id,trialID:t.id)
        XCTAssertEqual(s.run(id)!.trials[0].exclusions.count,3)
        try answerAll(s,id);try s.finish(id,expose:{_ in})
        XCTAssertEqual(ConditionSummary.evaluate(s.run(id)!).eligibleFamilies,0)
        XCTAssertTrue(s.run(id)!.trials.allSatisfy{!$0.exclusions.isEmpty})
    }
    @MainActor func testConsistentThreeFamiliesRequiredAndContraryEvidence() async throws {
        let s=await store(),id=try s.start(seed:0)
        try answerAll(s,id) { p in p.defenseChanged ? p.critical! : p.answers[0] }
        XCTAssertEqual(ConditionSummary.evaluate(s.run(id)!).eligibleFamilies,0) // no early conclusion
        try s.finish(id,expose:{_ in})
        let result=ConditionSummary.evaluate(s.run(id)!)
        XCTAssertEqual(result.eligibleFamilies,3);XCTAssertTrue(result.message.contains("防守改变后仍提交原着"));XCTAssertFalse(result.contrary.isEmpty)
        var run=s.run(id)!;run.trials[0].firstAnswer=nil
        XCTAssertEqual(ConditionSummary.evaluate(run).eligibleFamilies,2);XCTAssertTrue(ConditionSummary.evaluate(run).message.contains("暂不给"))
        run=s.run(id)!;run.trials[0].exclusions=["提示"]
        XCTAssertEqual(ConditionSummary.evaluate(run).eligibleFamilies,2)
        let other=await store(),otherID=try other.start(seed:1)
        try answerAll(other,otherID);try other.finish(otherID,expose:{_ in})
        XCTAssertTrue(ConditionSummary.evaluate(other.run(otherID)!).message.contains("尚无")) // all correct is not a blind-spot diagnosis
    }
    @MainActor func testCapturePatternAndDisagreement() async throws {
        let s=await store(),id=try s.start(seed:4)
        try answerAll(s,id) { p in p.captureOpportunity ? p.distractingCapture! : p.answers.first ?? "none" }
        try s.finish(id,expose:{_ in})
        XCTAssertTrue(ConditionSummary.evaluate(s.run(id)!).message.contains("有指定吃子机会时提交"))
        var r=s.run(id)!;let i=r.trials.firstIndex{$0.position.condition=="B"}!,t=r.trials[i]
        r.trials[i].firstAnswer=ConditionAnswer(submissionID:t.submissionID,choice:t.position.critical!,submittedAt:start,candidates:"",threat:"",correct:true)
        XCTAssertTrue(ConditionSummary.evaluate(r).message.contains("尚无"));XCTAssertFalse(ConditionSummary.evaluate(r).contrary.isEmpty)
    }
    @MainActor func testRealCompletionPlus24HoursTransferAndPoolExhaustion() async throws {
        var time=start;let s=await store(clock:{time}),id=try s.start(seed:7)
        try answerAll(s,id);time=time.addingTimeInterval(180);try s.finish(id,expose:{_ in})
        XCTAssertEqual(s.run(id)!.transferDueAt,time.addingTimeInterval(86400))
        XCTAssertThrowsError(try s.startTransfer(sourceID:id,seed:4,known:[]))
        time=time.addingTimeInterval(86399);XCTAssertThrowsError(try s.startTransfer(sourceID:id,seed:4,known:[]))
        time=time.addingTimeInterval(1)
        let key=ReforgeRules.key(s.positions.first{$0.family=="transfer"}!.fen)
        XCTAssertThrowsError(try s.startTransfer(sourceID:id,seed:4,known:[key]))
        let transfer=try s.startTransfer(sourceID:id,seed:4,known:[])
        XCTAssertEqual(s.run(transfer)!.trials.count,4);XCTAssertEqual(s.run(transfer)!.trials.filter{!$0.position.answers.isEmpty}.count,2)
        XCTAssertEqual(try s.startTransfer(sourceID:id,seed:999,known:[]),transfer)
        try answerAll(s,transfer);try s.finish(transfer,expose:{_ in})
        let again=try s.start(seed:1);try answerAll(s,again);try s.finish(again,expose:{_ in});time=time.addingTimeInterval(86400)
        XCTAssertThrowsError(try s.startTransfer(sourceID:again,seed:9,known:[]))
    }
    @MainActor func testExportPreservesVersionProofOrderAnswersAndOldData() async throws {
        let s=await store(),id=try s.start(seed:123)
        try answerAll(s,id);try s.finish(id,expose:{_ in})
        let capsule=try TimeCapsule.build(games:[GameRecord(moves:["e2e4"])],notebook:[],appVersion:"0.4.2 test",conditionStudy:s.exportArchive())
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .secondsSince1970
        let read=try decoder.decode(TimeCapsule.self,from:capsule.encoded()),c=try XCTUnwrap(read.conditionStudy)
        XCTAssertEqual(read.schemaVersion,6);XCTAssertEqual(read.games[0].moves,["e2e4"])
        XCTAssertEqual(c.catalog?.positions.count,16);XCTAssertEqual(c.engineChecks?.count,16);XCTAssertEqual(c.runs[0].seed,"123")
        XCTAssertEqual(c.runs[0].trials.map(\.position.digest),s.run(id)!.trials.map(\.position.digest))
        XCTAssertEqual(c.runs[0].completedCount,12);XCTAssertTrue(c.clockOrigin!.contains("injected"));XCTAssertEqual(c.exposures.count,24)
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:capsule.encoded()) as? [String:Any]);old.removeValue(forKey:"conditionStudy");old["schemaVersion"]=2
        XCTAssertNil(try decoder.decode(TimeCapsule.self,from:JSONSerialization.data(withJSONObject:old)).conditionStudy)
    }
    @MainActor func testCorruptDataAndExposureWriteFailurePreserveFirstAnswer() async throws {
        let bad=path();try FileManager.default.createDirectory(at:bad.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("broken original".utf8).write(to:bad);let s=await store(bad)
        XCTAssertNotNil(s.loadError);XCTAssertThrowsError(try s.start(seed:0));XCTAssertThrowsError(try s.exportArchive())
        XCTAssertEqual(try String(contentsOf:bad,encoding:.utf8),"broken original")
        let normal=await store(),id=try normal.start(seed:0)
        XCTAssertThrowsError(try normal.present(runID:id,known:[],expose:{_ in throw CocoaError(.fileWriteUnknown)}))
        XCTAssertNil(normal.run(id)!.current!.shownAt)
        let t=try XCTUnwrap(normal.present(runID:id,known:[],expose:{_ in}))
        XCTAssertThrowsError(try normal.submit(runID:id,trialID:t.id,submissionID:UUID(),choice:"none"))
        XCTAssertThrowsError(try normal.submit(runID:id,trialID:t.id,submissionID:t.submissionID,choice:"a1a8"))
        XCTAssertNil(normal.run(id)!.current!.firstAnswer)
    }

    @MainActor func testMalformedConditionsCannotProduceSummaryAndTransferIsNewToBuiltinLessons() async throws {
        let s=await store(),id=try s.start(seed:0)
        try answerAll(s,id);try s.finish(id,expose:{_ in})
        var r=s.run(id)!
        let family=r.trials[0].position.family, duplicate=r.trials[0]
        r.trials.removeAll{$0.position.family==family};r.trials.append(contentsOf:Array(repeating:duplicate,count:4))
        XCTAssertEqual(ConditionSummary.evaluate(r).eligibleFamilies,2)
        let known=try ReforgeRules().knownKeys(games:[],notes:[],seen:[])
        XCTAssertTrue(s.positions.filter{$0.family=="transfer"}.allSatisfy{!known.contains(ReforgeRules.key($0.fen))})
    }
    @MainActor func testSpecialRulesDedupeAndStalemate() throws {
        let rules=try ReforgeRules(),c=try ConditionCatalog.bundled()
        let ep=c.positions.first{$0.id=="transfer-en-passant"}!
        let f=try rules.engine.frames(fen:ep.fen)[0]
        XCTAssertTrue(f.replies.contains{$0.code=="e5d6"})
        XCTAssertNotEqual(ReforgeRules.key(ep.fen),ReforgeRules.key(ep.fen.replacingOccurrences(of:"d6",with:"-")))
        XCTAssertEqual(ReforgeRules.key(ep.fen),ReforgeRules.key(ep.fen.split(separator:" ").prefix(4).joined(separator:" ")+" 50 99"))
        XCTAssertNotEqual(ReforgeRules.key(ChessEngine.initialFEN),ReforgeRules.key(ChessEngine.initialFEN.replacingOccurrences(of:"KQkq",with:"-")))
        XCTAssertTrue(c.positions.first{$0.id=="transfer-back-rank"}!.proofMoves.contains("e1c1"))
        let stalemate="7k/5K2/6Q1/8/8/8/8/8 b - - 0 1"
        let stale=try rules.engine.frames(fen:stalemate)[0];XCTAssertFalse(stale.mate);XCTAssertTrue(stale.replies.isEmpty);XCTAssertEqual(try rules.mateMoves(stalemate),[])
        let promotion=DecisionStore(file:path()).catalog[3]
        XCTAssertEqual(try rules.mateMoves(promotion.fen),["f7f8q","f7f8r"])
        let pins=c.positions.filter{$0.family=="pinned-pawn"}
        for p in pins { let after=try rules.engine.frames(fen:p.fen,moves:[p.critical!]).last!;XCTAssertEqual(after.mate,!p.defenseChanged) }
    }
}
