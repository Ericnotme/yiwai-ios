import XCTest
@testable import YiwaiPractice

final class PersonalEvidenceTests:XCTestCase {
    private func path()->URL{FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("personal.json")}
    private func game()throws->GameRecord{try PersonalRules().parse(PersonalRules.demoPGN,side:"w")}
    private func pair()throws->[PersonalPosition]{
        let g=try game(),r=try PersonalRules(),e=try XCTUnwrap(MatePatternDetector().scan(g,side:"w",at:Date()).evidence.first),b=try XCTUnwrap(r.branches(e).first)
        return [PersonalPosition(id:"original",version:1,fen:e.fen,history:e.history,answers:e.answers,source:"synthetic",license:"test"),PersonalPosition(id:"branch",version:1,fen:b.fen,history:b.history,answers:[],source:"synthetic legal branch",license:"test")]
    }
    @MainActor private func fixture(clock:@escaping()->Date=Date.init,demo:Bool=false)throws->(PersonalStore,UUID){
        let s=PersonalStore(file:path(),clock:clock,clockOrigin:"injected tests only"),id=try s.add(game(),side:"w",demo:demo)
        let positions=try pair();try s.update(id){$0.rounds=[PersonalStore.round(positions,kind:"review",at:s.now,demo:demo)]};return(s,id)
    }
    @MainActor private func answer(_ s:PersonalStore,_ id:UUID)throws{
        while let t=s.item(id)?.active?.current {try s.present(id,known:[],expose:{_ in});try s.submit(id,trialID:t.id,submissionID:t.submissionID,choice:t.position.answers.first ?? "none")}
        try s.finish(id,expose:{_ in})
    }
    func testImportScopeMainlineSourceAndLegalCounterexample()throws{
        let r=try PersonalRules(),g=try game();XCTAssertEqual(g.moves.count,9);XCTAssertEqual(g.originalPGN,PersonalRules.demoPGN)
        let scan=try MatePatternDetector().scan(g,side:"w",at:Date()),e=try XCTUnwrap(scan.evidence.first)
        XCTAssertEqual(scan.misses,1);XCTAssertEqual(e.played,"h5f3");XCTAssertEqual(e.answers,["h5f7"])
        for b in try r.branches(e){XCTAssertEqual(b.history.dropLast(),e.history.dropLast());let v=try r.validate(history:b.history);XCTAssertTrue(v.answers.isEmpty);XCTAssertTrue(v.legal.contains("h5f7"))}
        for p in ["1. e5 *","[Variant \"Atomic\"]\n1. e4 *", "[SetUp \"1\"]\n[FEN \"7k/8/5KQ1/8/8/8/8/8 w - - 0 1\"]\n1. Qg5 *", "1. e4 * 1. d4 *",String(repeating:"♞",count:70000)]{XCTAssertThrowsError(try r.parse(p,side:"w"))}
        XCTAssertThrowsError(try r.parse(PersonalRules.demoPGN,side:""))
    }
    func testFullHistoryPromotionCastleEPAndCentipawnBudgetRejection()throws {
        let rules=try PersonalRules()
        let promoted=try rules.parse("1. a4 h5 2. a5 h4 3. a6 h3 4. axb7 hxg2 5. bxa8=Q gxh1=Q *",side:"w")
        XCTAssertEqual(promoted.moves.suffix(2),["b7a8q","g2h1q"])
        _=try rules.validate(history:promoted.moves)
        for pgn in ["1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O *","1. e4 a6 2. e5 d5 3. exd6 *"] {_=try rules.validate(history:rules.parse(pgn,side:"w").moves)}
        let p=try pair()[1],v=try rules.validate(history:p.history),move=v.legal[0]
        func cp(_ budget:Int,_ value:Int)->PersonalProbe {
            PersonalProbe(evaluation:ReviewEvaluation(cp:Double(value),win:50,depth:5,terminal:false,draw:false,mate:nil,winner:nil,best:move,pv:[move],nodes:20,legalCount:v.legal.count),rawScore:.init(type:"cp",value:value),elapsedMS:budget,stopReason:"test",budgetMS:budget,history:p.history,initialFEN:ChessEngine.initialFEN)
        }
        XCTAssertTrue(try rules.stable([cp(450,10),cp(1400,50)],history:p.history,answers:[]))
        XCTAssertFalse(try rules.stable([cp(450,10),cp(1400,200)],history:p.history,answers:[]))
    }
    func testPublicActualPGNNegativePathAndPerformance()throws {
        // Existing public fixture: Fischer–Spassky 1972 round 6, PGN Mentor.
        // This is a negative-path check, not learning-effect evidence.
        let pgn="""
[Event "World Championship 28th"]
[Site "Reykjavik"]
[Date "1972.??.??"]
[Round "6"]
[White "Fischer, Robert James"]
[Black "Spassky, Boris V"]
[Result "1-0"]
[WhiteElo "2785"]
[BlackElo "2660"]
[ECO "D59"]

1.c4 e6 2.Nf3 d5 3.d4 Nf6 4.Nc3 Be7 5.Bg5 O-O 6.e3 h6 7.Bh4 b6 8.cxd5 Nxd5
9.Bxe7 Qxe7 10.Nxd5 exd5 11.Rc1 Be6 12.Qa4 c5 13.Qa3 Rc8 14.Bb5 a6 15.dxc5 bxc5
16.O-O Ra7 17.Be2 Nd7 18.Nd4 Qf8 19.Nxe6 fxe6 20.e4 d4 21.f4 Qe7 22.e5 Rb8
23.Bc4 Kh8 24.Qh3 Nf8 25.b3 a5 26.f5 exf5 27.Rxf5 Nh7 28.Rcf1 Qd8 29.Qg3 Re7
30.h4 Rbb7 31.e6 Rbc7 32.Qe5 Qe8 33.a4 Qd8 34.R1f2 Qe8 35.R2f3 Qd8 36.Bd3 Qe8
37.Qe4 Nf6 38.Rxf6 gxf6 39.Rxf6 Kg8 40.Bc4 Kh8 41.Qf4  1-0
"""
        let began=Date(),game=try PersonalRules().parse(pgn,side:"w"),scan=try MatePatternDetector().scan(game,side:"w",at:Date())
        XCTAssertEqual(game.moves.count,81);XCTAssertEqual(scan.examined,41);XCTAssertEqual(scan.misses,0)
        print("PERSONAL_PUBLIC_PGN_SECONDS=\(Date().timeIntervalSince(began))")
    }
    func testAllAnswersPinsStalemateAndRealStateNovelty()throws{
        let rules=try ReforgeRules()
        XCTAssertEqual(try rules.mateMoves("7k/5P1p/5K2/8/8/8/8/8 w - - 0 1"),["f7f8q","f7f8r"])
        XCTAssertEqual(try rules.mateMoves("7k/5K2/6Q1/8/8/8/8/8 b - - 0 1"),[])
        XCTAssertTrue(PersonalRules.near(ChessEngine.initialFEN,try ChessEngine().frames(fen:ChessEngine.initialFEN,moves:["e2e4"]).last!.fen))
        XCTAssertTrue(PersonalRules.near("7k/8/5KQ1/8/8/8/8/8 w - - 0 1","k7/8/1QK5/8/8/8/8/8 w - - 10 40"))
        XCTAssertNotEqual(ReforgeRules.key("8/8/8/3pP3/8/8/4K3/7k w - d6 0 12"),ReforgeRules.key("8/8/8/3pP3/8/8/4K3/7k w - - 0 12"))
    }
    func testUnstableBudgetAndWrongPVFailClosed()throws{
        let p=try pair()[0],rules=try PersonalRules()
        func probe(_ budget:Int,_ score:PersonalProbe.Score,_ pv:[String])->PersonalProbe{
            PersonalProbe(evaluation:ReviewEvaluation(cp:10000,win:100,depth:5,terminal:false,draw:false,mate:score.type=="mate" ? abs(score.value):nil,winner:"w",best:pv.first,pv:pv,nodes:100,legalCount:40),rawScore:score,elapsedMS:budget,stopReason:"test exact",budgetMS:budget,history:p.history,initialFEN:ChessEngine.initialFEN)
        }
        let a=probe(450,.init(type:"mate",value:1),["h5f7"]),b=probe(1400,.init(type:"mate",value:1),["h5f7"])
        XCTAssertTrue(try rules.stable([a,b],history:p.history,answers:p.answers))
        XCTAssertFalse(try rules.stable([a],history:p.history,answers:p.answers))
        XCTAssertFalse(try rules.stable([a,probe(1400,.init(type:"mate",value:2),["h5f7"])],history:p.history,answers:p.answers))
        XCTAssertFalse(try rules.stable([a,b],history:p.history,answers:[]))
        XCTAssertThrowsError(try rules.stable([a,probe(1400,.init(type:"mate",value:1),["h5f7","e8e7"])],history:p.history,answers:p.answers))
        let encoded=try JSONEncoder().encode(b),read=try JSONDecoder().decode(PersonalProbe.self,from:encoded)
        XCTAssertEqual(read.rawScore.type,"mate");XCTAssertEqual(read.evaluation.pv,["h5f7"]);XCTAssertTrue(read.scorePerspective.contains("white only"))
    }
    @MainActor func testFirstAnswerIdempotentCrashHintAndMissingNotZero()throws{
        let(s,id)=try fixture();defer{try? FileManager.default.removeItem(at:s.file.deletingLastPathComponent())}
        XCTAssertEqual(try s.add(game(),side:"w",demo:false),id)
        try s.present(id,known:[],expose:{_ in});let t=try XCTUnwrap(s.item(id)?.active?.current)
        try s.draft(id,candidates:"Q?",reason:"my current thought");try s.hint(id)
        let reopened=PersonalStore(file:s.file);XCTAssertEqual(reopened.item(id)?.active?.current?.reason,"my current thought")
        try reopened.present(id,known:[ReforgeRules.key(t.position.fen)],expose:{_ in XCTFail("resume must not expose twice")})
        try reopened.submit(id,trialID:t.id,submissionID:t.submissionID,choice:"none")
        try reopened.submit(id,trialID:t.id,submissionID:t.submissionID,choice:"none")
        XCTAssertThrowsError(try reopened.submit(id,trialID:t.id,submissionID:t.submissionID,choice:t.position.answers.first ?? "h5f7"))
        XCTAssertThrowsError(try reopened.submit(id,trialID:t.id,submissionID:UUID(),choice:"none"))
        XCTAssertThrowsError(try reopened.exportArchive());XCTAssertNil(reopened.item(id)?.rounds[0].feedbackAt)
        try reopened.finish(id,expose:{_ in});let round=reopened.item(id)!.rounds[0]
        XCTAssertEqual(round.trials.compactMap(\.first).count,1);XCTAssertEqual(round.trials.filter{$0.first==nil}.count,1)
        XCTAssertEqual(round.trials.first{$0.id==t.id}?.first?.reason,"my current thought")
        XCTAssertTrue(round.trials.first{$0.id==t.id}!.first!.exclusions.contains("hint or self-reported exposure"))
        XCTAssertTrue(round.trials.allSatisfy{!$0.exclusions.isEmpty})
        try reopened.recollect(id,text:"later recall",correction:"not my reason")
        XCTAssertEqual(reopened.item(id)?.rounds[0].trials.first{$0.id==t.id}?.first?.reason,"my current thought")
    }
    @MainActor func testMatchedPracticeDueTransferNoveltyAndExhaustion()throws{
        var time=Date(timeIntervalSince1970:1792800000);let(s,id)=try fixture(clock:{time})
        defer{try? FileManager.default.removeItem(at:s.file.deletingLastPathComponent())}
        try answer(s,id);try s.startCatalog(id,kind:"practice",known:[]);try answer(s,id)
        XCTAssertEqual(s.item(id)?.dueAt,time.addingTimeInterval(86400));XCTAssertThrowsError(try s.startCatalog(id,kind:"transfer",known:[]))
        time=time.addingTimeInterval(86400);try s.startCatalog(id,kind:"transfer",known:[])
        let round=try XCTUnwrap(s.item(id)?.active);XCTAssertEqual(round.trials.count,2);XCTAssertEqual(round.trials.filter{$0.position.answers.isEmpty}.count,1)
        XCTAssertTrue(round.trials.allSatisfy{$0.position.source.contains("NOT personal counterfactual")})
        for t in round.trials {XCTAssertEqual(t.position.catalogProof?.digest,t.position.catalogCheck?.digest);XCTAssertNotNil(t.position.catalogProof)}
        for t in round.trials {for old in s.item(id)!.rounds.dropLast().flatMap(\.trials){XCTAssertFalse(PersonalRules.near(t.position.fen,old.position.fen))}}
        try answer(s,id);XCTAssertThrowsError(try s.startCatalog(id,kind:"transfer",known:[]))
        let(s2,id2)=try fixture();defer{try? FileManager.default.removeItem(at:s2.file.deletingLastPathComponent())};try answer(s2,id2)
        let all=Set(try ConditionCatalog.bundled().positions.map{ReforgeRules.key($0.fen)})
        XCTAssertThrowsError(try s2.startCatalog(id2,kind:"practice",known:all));XCTAssertEqual(s2.item(id2)?.rounds.count,1)
    }
    @MainActor func testCapsuleContainsAllLayersAndOldSchemaStillLoads()throws{
        let(s,id)=try fixture(demo:true);defer{try? FileManager.default.removeItem(at:s.file.deletingLastPathComponent())}
        try answer(s,id);try s.recollect(id,text:"after",correction:"uncertain")
        let archive=try s.exportArchive(),capsule=try TimeCapsule.build(games:[],notebook:[],appVersion:"unreleased test",personalEvidence:archive)
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .secondsSince1970
        let decoded=try decoder.decode(TimeCapsule.self,from:capsule.encoded())
        XCTAssertEqual(decoded.schemaVersion,6);XCTAssertEqual(decoded.personalEvidence?.cases[0].game.originalPGN,PersonalRules.demoPGN)
        XCTAssertEqual(decoded.personalEvidence?.cases[0].hypothesisText,s.item(id)?.hypothesis)
        var previous=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(s.item(id)!)) as? [String:Any]);previous.removeValue(forKey:"hypothesisText")
        let previousCase=try JSONDecoder().decode(PersonalCase.self,from:JSONSerialization.data(withJSONObject:previous))
        XCTAssertEqual(previousCase.hypothesis,PersonalCase.initialHypothesis)
        XCTAssertEqual(decoded.personalEvidence?.cases[0].rounds[0].trials.compactMap(\.first).count,2)
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:capsule.encoded()) as? [String:Any]);old.removeValue(forKey:"personalEvidence");old["schemaVersion"]=3
        XCTAssertNil(try decoder.decode(TimeCapsule.self,from:JSONSerialization.data(withJSONObject:old)).personalEvidence)
    }
    @MainActor func testFailedSaveAndCorruptStoreDoNotReplaceRecords()throws{
        let file=path();try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        try Data("broken".utf8).write(to:file);let s=PersonalStore(file:file)
        XCTAssertNotNil(s.error);XCTAssertThrowsError(try s.add(game(),side:"w",demo:false));XCTAssertEqual(try String(contentsOf:file),"broken")
    }
    @MainActor func testRealEngineBlackPerspectiveAndLegalProof()async throws {
        let g=try PersonalRules().parse("1. f3 e5 2. g4 Nc6 3. h4 Qxh4# 0-1",side:"b"),r=try PersonalRules()
        let e=try XCTUnwrap(MatePatternDetector().scan(g,side:"b",at:Date()).evidence.first),b=try XCTUnwrap(r.branches(e).first)
        XCTAssertEqual(e.answers,["d8h4"])
        for (history,answers) in [(e.history,e.answers),(b.history,[])] {
            var probes:[PersonalProbe]=[]
            for duration in [450,1400] {let engine=StockfishReviewEngine();defer{engine.cancel()};probes.append(try await engine.probe(history:history,duration:duration))}
            XCTAssertTrue(try r.stable(probes,history:history,answers:answers))
            if !answers.isEmpty {XCTAssertEqual(probes[0].evaluation.winner,"b");XCTAssertEqual(probes[0].rawScore.value,1)}
            else if probes[0].rawScore.type=="cp" {XCTAssertEqual(probes[0].evaluation.cp,-Double(probes[0].rawScore.value))}
        }
    }
    @MainActor func testRealEnginePipelineOfflineCompleteEvidenceAndCancellation()async throws{
        let file=path(),s=PersonalStore(file:file),id=try s.add(game(),side:"w",demo:true),pipeline=PersonalPipeline()
        defer{pipeline.cancel();try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
        let began=Date();pipeline.run(id,store:s)
        for _ in 0..<1800 {if !pipeline.running{break};try await Task.sleep(for:.milliseconds(100))}
        XCTAssertFalse(pipeline.running);XCTAssertNil(pipeline.error)
        let item=try XCTUnwrap(s.item(id));XCTAssertEqual(item.status,"ready",item.attempts.map(\.outcome).joined(separator:"\n"))
        XCTAssertEqual(item.rounds[0].trials.count,2)
        for t in item.rounds[0].trials {XCTAssertTrue(try PersonalRules().stable(t.position.probes,history:t.position.history,answers:t.position.answers))}
        let enc=JSONEncoder();enc.outputFormatting = [.prettyPrinted,.sortedKeys];enc.dateEncodingStrategy = .secondsSince1970
        let attachment=XCTAttachment(data:try enc.encode(item),uniformTypeIdentifier:"public.json");attachment.name="personal-real-engine-synthetic-evidence";attachment.lifetime = .keepAlways;add(attachment)
        print("PERSONAL_PIPELINE_ELAPSED_SECONDS=\(Date().timeIntervalSince(began))")
        let negative=try PersonalRules().parse("1. e4 e5 2. Nf3 Nc6 *",side:"w"),negativeID=try s.add(negative,side:"w",demo:false)
        pipeline.run(negativeID,store:s);pipeline.cancel();try await Task.sleep(for:.milliseconds(300))
        XCTAssertTrue(s.item(negativeID)!.rounds.isEmpty)
        pipeline.run(negativeID,store:s);for _ in 0..<100{if !pipeline.running{break};try await Task.sleep(for:.milliseconds(100))}
        XCTAssertEqual(s.item(negativeID)?.status,"complete-no-pair");XCTAssertTrue(s.item(negativeID)!.rounds.isEmpty)
    }
}
