import XCTest
@testable import YiwaiPractice

final class LearningPatternTests: XCTestCase {
    private let first = GameRecord(initialFEN:"7k/8/5KQ1/8/8/8/8/8 w - - 0 1",moves:["g6g5"],source:"pgn")
    private let second = GameRecord(initialFEN:"7k/1R6/5K2/8/8/8/8/R7 w - - 0 1",moves:["a1a2"],source:"pgn")
    private func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("patterns.json") }
    func testImportedPGNProducesExactRuleEvidenceAndNoInventedReason() throws {
        struct Imported: Decodable { let initialFen:String; let moves:[String] }
        let pgn="[SetUp \"1\"]\n[FEN \"\(first.initialFEN)\"]\n\n1. Qg5 *"
        let input: Imported = try ChessEngine().call("importPosition",[pgn,"pgn"])
        let g = GameRecord(initialFEN:input.initialFen,moves:input.moves)
        let scan = try MatePatternDetector().scan(g,side:"w",at:Date())
        XCTAssertEqual(scan.examined,1); XCTAssertEqual(scan.misses,1)
        XCTAssertEqual(scan.evidence[0].answers,["g6g7"]); XCTAssertEqual(scan.evidence[0].replyExamples,["Kh7"])
        XCTAssertEqual(scan.evidence[0].history,[]); XCTAssertTrue(scan.evidence[0].explanation.contains("可能仍然获胜"))
        XCTAssertTrue(try MatePatternDetector().scan(g,side:"b",at:Date()).evidence.isEmpty)
    }
    @MainActor func testDuplicateImportsSameGameAndCounterChangesNeverCreateRepetition() throws {
        let file = path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file), detector=try MatePatternDetector()
        try store.saveScan(detector.scan(first,side:"w",at:Date()),game:first)
        var duplicate=first; duplicate.id=UUID(); duplicate.initialFEN=duplicate.initialFEN.replacingOccurrences(of:"0 1",with:"7 22")
        try store.saveScan(detector.scan(duplicate,side:"w",at:Date()),game:duplicate)
        XCTAssertEqual(store.data.scans?.count,1); XCTAssertFalse(store.patternSummary(games:[first,duplicate]).repeated)
        var sameGame=first; sameGame.moves=["g6g5","h8h7","g5g6"]
        try store.saveScan(detector.scan(sameGame,side:"w",at:Date()),game:sameGame)
        // Only scans for histories still present count; different metadata doesn't make another game.
        XCTAssertFalse(store.patternSummary(games:[sameGame]).repeated)
    }
    @MainActor func testTwoDistinctGamesPositionsAndCorrectedSide() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file), detector=try MatePatternDetector()
        for g in [first,second] { try store.saveScan(detector.scan(g,side:"w",at:Date()),game:g) }
        XCTAssertTrue(store.patternSummary(games:[first,second]).repeated)
        let reopened=DecisionStore(file:file); XCTAssertEqual(reopened.data.scans?.count,2)
        try reopened.saveScan(detector.scan(second,side:"b",at:Date()),game:second)
        XCTAssertFalse(reopened.patternSummary(games:[first,second]).repeated)
    }
    @MainActor func testEvidencePracticeThenDifferentDueTestAndCompleteExport() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        var clock=Date(timeIntervalSince1970:1792756800)
        let store=DecisionStore(file:file,clock:{clock}), scan=try MatePatternDetector().scan(first,side:"w",at:clock)
        try store.saveScan(scan,game:first)
        let evidence=scan.evidence[0], item=try store.createEvidencePlan(evidence,game:first)
        XCTAssertEqual(try store.createEvidencePlan(evidence,game:first).id,item.id)
        XCTAssertEqual(store.data.notes[0].reason,""); XCTAssertEqual(store.data.notes[0].origin,.rulesEvidence)
        let practice=try XCTUnwrap(store.begin(itemID:item.id,games:[first],practice:true))
        clock=clock.addingTimeInterval(31); try store.submit(sessionID:practice.id,move:practice.puzzle.answers[0])
        XCTAssertFalse(store.session(practice.id)!.countedIndependent)
        XCTAssertEqual(store.data.items[0].dueAt,clock.addingTimeInterval(86400))
        clock=store.data.items[0].dueAt
        let test=try XCTUnwrap(store.begin(itemID:item.id,games:[first]))
        XCTAssertNotEqual(ReforgeRules.key(test.puzzle.fen),ReforgeRules.key(practice.puzzle.fen))
        XCTAssertNotEqual(ReforgeRules.key(test.puzzle.fen),ReforgeRules.key(evidence.fen))
        try store.submit(sessionID:test.id,move:test.puzzle.answers[0]); XCTAssertTrue(store.session(test.id)!.countedIndependent)
        let export=try TimeCapsule.build(games:[first],notebook:[],appVersion:"0.4.0 test",decisions:store.exportArchive()).encoded()
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let saved=try XCTUnwrap(decoder.decode(TimeCapsule.self,from:export).decisions)
        XCTAssertEqual(saved.scans?[0].evidence[0].id,saved.notes[0].evidence?.id)
        XCTAssertEqual(saved.sessions.map(\.kind),["practice","new"])
        let attachment=XCTAttachment(data:export,uniformTypeIdentifier:"public.json"); attachment.name="learning-loop-synthetic-export.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testLegacyDecisionArchiveAndNotesStillDecode() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file)
        try store.record(game:first,ply:0,candidates:"Qg7",reason:"原来的原话",origin:.recollection,tag:.allReplies)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        json.removeValue(forKey:"scans")
        try JSONSerialization.data(withJSONObject:json).write(to:file)
        let old=DecisionStore(file:file)
        XCTAssertNil(old.loadError); XCTAssertEqual(old.data.notes[0].reason,"原来的原话"); XCTAssertNil(old.data.notes[0].evidence)
    }
    @MainActor func testStaleEvidenceAndDiskFailureAreNotAccepted() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file), scan=try MatePatternDetector().scan(first,side:"w",at:Date())
        XCTAssertThrowsError(try store.saveScan(scan,game:second))
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true)
        XCTAssertThrowsError(try store.saveScan(scan,game:first)); XCTAssertNil(store.data.scans)
    }
    func testCancelledScanAndNoOpportunityAreHonest() throws {
        let token=SearchCancellation(); token.cancel()
        XCTAssertThrowsError(try MatePatternDetector(cancellation:token).scan(first,side:"w",at:Date()))
        let result=try MatePatternDetector().scan(GameRecord(moves:["e2e4","e7e5"]),side:"w",at:Date())
        XCTAssertEqual(result.misses,0); XCTAssertTrue(result.evidence.isEmpty)
    }
    func testEvidenceUsesActualFENMoveNumber() throws {
        var game = first; game.initialFEN = game.initialFEN.replacingOccurrences(of:"0 1",with:"0 23")
        let evidence = try XCTUnwrap(MatePatternDetector().scan(game,side:"w",at:Date()).evidence.first)
        XCTAssertEqual(evidence.moveNumber,23); XCTAssertTrue(evidence.explanation.contains("第 23 回合"))
    }
    @MainActor func testExistingReasonLinksToEvidenceWithoutOverwritingUserWords() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file)
        try store.record(game:first,ply:0,candidates:"Qg5",reason:"我想限制王",origin:.recollection,tag:.unconfirmed)
        let original = store.data.notes[0], itemID = store.data.items[0].id
        let scan=try MatePatternDetector().scan(first,side:"w",at:Date())
        try store.saveScan(scan,game:first)
        XCTAssertEqual(try store.createEvidencePlan(scan.evidence[0],game:first).id,itemID)
        XCTAssertEqual(store.data.notes.count,1); XCTAssertEqual(store.data.notes[0].reason,original.reason)
        XCTAssertEqual(store.data.notes[0].origin,.recollection); XCTAssertEqual(store.data.notes[0].recordedAt,original.recordedAt)
        XCTAssertEqual(store.data.notes[0].evidence,scan.evidence[0]); XCTAssertEqual(store.data.notes[0].tag,.allReplies)
    }

}
