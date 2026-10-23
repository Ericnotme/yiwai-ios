import XCTest
@testable import YiwaiPractice

final class DecisionReforgeTests: XCTestCase {
    private func file() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("decisions.json") }
    private let start = Date(timeIntervalSince1970:1792584000)
    private let original = GameRecord(initialFEN:"7k/8/5KQ1/8/8/8/8/8 w - - 0 1",source:"fen")
    @MainActor private func add(_ store: DecisionStore, tag: DecisionTag = .allReplies) throws -> ReforgeItem {
        _ = try store.record(game:original,ply:0,candidates:"Qg7?",reason:"我想先检查王的所有出口。",origin:.recollection,tag:tag)
        return try XCTUnwrap(store.data.items.first)
    }
    @MainActor func testEveryCatalogAnswerIsLegalMateAndAnswerSetComplete() throws {
        let fen = ChessEngine.initialFEN
        XCTAssertEqual(ReforgeRules.key(fen),ReforgeRules.key(fen.replacingOccurrences(of:"0 1",with:"9 22")))
        XCTAssertNotEqual(ReforgeRules.key(fen),ReforgeRules.key(fen.replacingOccurrences(of:" w ",with:" b ")))
        XCTAssertNotEqual(ReforgeRules.key(fen),ReforgeRules.key(fen.replacingOccurrences(of:"KQkq",with:"KQ")))
        XCTAssertNotEqual(ReforgeRules.key("7k/8/8/3pP3/8/8/8/K7 w - d6 0 12"),ReforgeRules.key("7k/8/8/3pP3/8/8/8/K7 w - - 0 12"))
        let store = DecisionStore(file:file()), rules = try ReforgeRules()
        XCTAssertEqual(store.catalog.count,5)
        XCTAssertEqual(Set(store.catalog.map { ReforgeRules.key($0.fen) }).count,5)
        let known = try rules.knownKeys(games:[],notes:[],seen:[])
        for puzzle in store.catalog {
            XCTAssertFalse(known.contains(ReforgeRules.key(puzzle.fen)))
            XCTAssertEqual(try rules.mateMoves(puzzle.fen),puzzle.answers.sorted())
            for move in puzzle.answers {
                let result = try rules.engine.frames(fen:puzzle.fen,moves:[move]).last!
                XCTAssertTrue(result.mate); XCTAssertTrue(result.replies.isEmpty)
            }
            XCTAssertFalse(puzzle.source.isEmpty); XCTAssertTrue(puzzle.license.contains("GPL"))
        }
        XCTAssertEqual(store.catalog[3].answers.sorted(),["f7f8q","f7f8r"])
    }
    @MainActor func testOriginSkipLimitAndUserTagCorrectionPersist() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        let store = DecisionStore(file:path,clock:{self.start})
        let game = GameRecord(moves:["e2e4","e7e5"])
        XCTAssertThrowsError(try store.record(game:game,ply:0,candidates:"old",reason:"",origin:.beforeMove,tag:.allReplies))
        let note = try store.record(game:game,ply:2,candidates:"Nf3 或 Bc4",reason:"  原话\n不确定 ♞",origin:.beforeMove,tag:.unconfirmed)
        XCTAssertEqual(store.data.items.count,1)
        try store.changeTag(noteID:note.id,tag:.allReplies)
        let skipped = try store.record(game:game,ply:0,candidates:"discard",reason:"discard",origin:.recollection,tag:.allReplies,skipped:true)
        XCTAssertTrue(skipped.skipped); XCTAssertEqual(skipped.candidates,""); XCTAssertEqual(store.data.items.count,1)
        XCTAssertFalse(store.canRecord(gameID:game.id))
        XCTAssertThrowsError(try store.record(game:game,ply:1,candidates:"third",reason:"",origin:.recollection,tag:.allReplies))
        let reopened = DecisionStore(file:path)
        XCTAssertEqual(reopened.data.notes[0].reason,"  原话\n不确定 ♞")
        XCTAssertEqual(reopened.data.notes[0].origin,.beforeMove)
        XCTAssertEqual(reopened.data.notes[0].tagChanges.map(\.tag),[.unconfirmed,.allReplies])
        XCTAssertEqual(reopened.data.notes[0].history,["e2e4","e7e5"])
        XCTAssertTrue(reopened.data.notes[0].tagChanges.allSatisfy {$0.author == "user"})
    }
    @MainActor func testDueTimeIndependentPassesAndNoFakeElapsedDays() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        var clock = start
        let store = DecisionStore(file:path,clock:{clock},clockOrigin:"injected unit test clock")
        let item = try add(store); XCTAssertEqual(item.dueAt,start.addingTimeInterval(86400))
        clock = item.dueAt
        let a = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        clock = clock.addingTimeInterval(42)
        try store.submit(sessionID:a.id,move:a.puzzle.answers[0])
        XCTAssertEqual(store.session(a.id)?.elapsedSeconds,42)
        XCTAssertTrue(store.session(a.id)?.countedIndependent == true)
        XCTAssertEqual(store.data.items[0].independentPasses,1)
        XCTAssertEqual(store.data.items[0].dueAt,clock.addingTimeInterval(3*86400))
        clock = store.data.items[0].dueAt
        let b = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        XCTAssertNotEqual(a.puzzle.id,b.puzzle.id)
        try store.submit(sessionID:b.id,move:b.puzzle.answers[0])
        XCTAssertEqual(store.data.items[0].independentPasses,2)
        XCTAssertEqual(store.data.items[0].dueAt,clock.addingTimeInterval(7*86400))
        XCTAssertEqual(store.data.items[0].status,"本主题已两次独立通过")
        let reopened = DecisionStore(file:path,clock:{clock})
        XCTAssertEqual(reopened.data.sessions.count,2); XCTAssertEqual(reopened.data.items[0].independentPasses,2)
    }
    @MainActor func testHintPersistsBeforeFeedbackAndFirstAnswerCannotBeReplaced() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        var clock = start
        let store = DecisionStore(file:path,clock:{clock}); let item = try add(store)
        clock = item.dueAt
        let session = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        XCTAssertNil(store.session(session.id)?.outcome)
        try store.revealHint(sessionID:session.id)
        let reopened = DecisionStore(file:path,clock:{clock})
        XCTAssertEqual(try reopened.begin(itemID:item.id,games:[original])?.id,session.id)
        XCTAssertNotNil(reopened.session(session.id)?.hintAt)
        try reopened.submit(sessionID:session.id,move:session.puzzle.answers[0])
        XCTAssertFalse(reopened.session(session.id)!.countedIndependent)
        XCTAssertEqual(reopened.data.items[0].independentPasses,0)
        XCTAssertEqual(reopened.data.items[0].dueAt,clock.addingTimeInterval(86400))
        XCTAssertThrowsError(try reopened.submit(sessionID:session.id,move:"c1c2"))
        XCTAssertEqual(reopened.session(session.id)?.firstMove,session.puzzle.answers[0])
        XCTAssertThrowsError(try reopened.revealHint(sessionID:session.id))
    }
    @MainActor func testEarlyOriginalWrongAndSkippedNeverIncreaseMastery() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        var clock = start
        let store = DecisionStore(file:path,clock:{clock}); let item = try add(store)
        let early = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        XCTAssertTrue(early.early); try store.submit(sessionID:early.id,move:early.puzzle.answers[0])
        XCTAssertFalse(store.session(early.id)!.countedIndependent)
        clock = store.data.items[0].dueAt
        let repeatOriginal = try XCTUnwrap(store.begin(itemID:item.id,games:[original],original:true))
        XCTAssertEqual(repeatOriginal.kind,"original")
        try store.submit(sessionID:repeatOriginal.id,move:repeatOriginal.puzzle.answers[0])
        XCTAssertFalse(store.session(repeatOriginal.id)!.countedIndependent)
        clock = store.data.items[0].dueAt
        let wrong = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        let legalWrong = try XCTUnwrap(try ChessEngine().frames(fen:wrong.puzzle.fen)[0].replies.first { !wrong.puzzle.answers.contains($0.code) })
        try store.submit(sessionID:wrong.id,move:legalWrong.code)
        XCTAssertEqual(store.session(wrong.id)?.outcome,"incorrect")
        clock = store.data.items[0].dueAt
        let skip = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        try store.submit(sessionID:skip.id,move:nil,skipped:true)
        XCTAssertEqual(store.session(skip.id)?.outcome,"skipped"); XCTAssertNil(store.session(skip.id)?.firstMove)
        XCTAssertEqual(store.data.items[0].independentPasses,0)
    }
    @MainActor func testKnownGameHistoryCountersAndExposureExhaustion() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        var clock = start
        let store = DecisionStore(file:path,clock:{clock}); let item = try add(store)
        var seenGame = GameRecord(initialFEN:store.catalog[0].fen)
        seenGame.initialFEN = seenGame.initialFEN.replacingOccurrences(of:"0 1",with:"7 22")
        let session = try XCTUnwrap(store.begin(itemID:item.id,games:[original,seenGame]))
        XCTAssertNotEqual(session.puzzle.id,store.catalog[0].id)
        try store.submit(sessionID:session.id,move:nil,skipped:true)
        // A different fullmove counter cannot turn a known position into a new puzzle.
        let everyPuzzle = store.catalog.map { GameRecord(initialFEN:$0.fen) }
        XCTAssertNil(try store.begin(itemID:item.id,games:everyPuzzle))
        XCTAssertTrue(store.data.items[0].waitingReason!.contains("未见过"))
        XCTAssertEqual(store.data.sessions.count,1)
        // Seen state survives restart even if that game is not in the passed list anymore.
        let reopened = DecisionStore(file:path,clock:{clock})
        var used = Set([session.puzzle.id])
        for _ in 0..<4 {
            clock = clock.addingTimeInterval(86400)
            let s = try XCTUnwrap(reopened.begin(itemID:item.id,games:[original]))
            XCTAssertFalse(used.contains(s.puzzle.id)); used.insert(s.puzzle.id)
            try reopened.submit(sessionID:s.id,move:nil,skipped:true)
        }
        XCTAssertNil(try reopened.begin(itemID:item.id,games:[original]))
        XCTAssertEqual(used.count,5)
    }
    @MainActor func testBadCatalogAndUnconfirmedTagDegradeHonestly() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        let valid = try XCTUnwrap(DecisionStore(file:file()).catalog.first)
        let bad = ReforgePuzzle(id:"broken",version:1,theme:valid.theme,fen:valid.fen,answers:["c1c2"],hint:"",explanation:"",source:valid.source,license:valid.license,validation:valid.validation)
        let store = DecisionStore(file:path,catalog:[bad]); let item = try add(store,tag:.unconfirmed)
        XCTAssertTrue(store.catalog.isEmpty)
        XCTAssertNil(try store.begin(itemID:item.id,games:[original]))
        XCTAssertTrue(store.data.items[0].waitingReason!.contains("标签"))
        try store.changeTag(noteID:store.data.notes[0].id,tag:.allReplies)
        XCTAssertNil(try store.begin(itemID:item.id,games:[original]))
        XCTAssertTrue(store.data.items[0].waitingReason!.contains("没有已验证"))
        XCTAssertTrue(store.data.sessions.isEmpty)
    }
    @MainActor func testFailuresKeepOriginalDataAndDoNotExposeHintOrSubmit() throws {
        let path = file(), backup = path.deletingLastPathComponent().appendingPathComponent("backup.json")
        defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        let store = DecisionStore(file:path); let item = try add(store)
        let s = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        let originalData = try Data(contentsOf:path)
        try FileManager.default.moveItem(at:path,to:backup); try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
        XCTAssertThrowsError(try store.revealHint(sessionID:s.id)); XCTAssertNil(store.session(s.id)?.hintAt)
        XCTAssertThrowsError(try store.submit(sessionID:s.id,move:s.puzzle.answers[0])); XCTAssertFalse(store.session(s.id)!.finished)
        XCTAssertEqual(try Data(contentsOf:backup),originalData)
        try FileManager.default.removeItem(at:path); try FileManager.default.moveItem(at:backup,to:path)
        try store.submit(sessionID:s.id,move:s.puzzle.answers[0]); XCTAssertTrue(store.session(s.id)!.finished)
        try Data("corrupt".utf8).write(to:path)
        let broken = DecisionStore(file:path)
        XCTAssertThrowsError(try broken.exportArchive())
        XCTAssertEqual(try String(contentsOf:path),"corrupt")
    }
    @MainActor func testExportConnectsOriginVersionHintAnswerAndSchedule() throws {
        let path = file(); defer { try? FileManager.default.removeItem(at:path.deletingLastPathComponent()) }
        let store = DecisionStore(file:path,clock:{self.start},clockOrigin:"injected unit test clock")
        let item = try add(store); let s = try XCTUnwrap(store.begin(itemID:item.id,games:[original]))
        try store.revealHint(sessionID:s.id); try store.submit(sessionID:s.id,move:s.puzzle.answers[0])
        let archive = try store.exportArchive()
        let capsule = try TimeCapsule.build(games:[original],notebook:[],appVersion:"test",decisions:archive)
        let bytes = try capsule.encoded(), decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let exported = try XCTUnwrap(try decoder.decode(TimeCapsule.self,from:bytes).decisions)
        XCTAssertEqual(exported.notes[0].gameID,capsule.games[0].id)
        XCTAssertEqual(exported.items[0].decisionID,exported.notes[0].id)
        XCTAssertEqual(exported.sessions[0].itemID,exported.items[0].id)
        XCTAssertEqual(exported.sessions[0].puzzle.version,1)
        XCTAssertEqual(exported.sessions[0].firstMove,s.puzzle.answers[0])
        XCTAssertNotNil(exported.sessions[0].hintAt); XCTAssertFalse(exported.sessions[0].countedIndependent)
        XCTAssertEqual(exported.items[0].dueAt,start.addingTimeInterval(86400))
        XCTAssertEqual(exported.clockOrigin,"injected unit test clock")
        let attachment = XCTAttachment(data:bytes,uniformTypeIdentifier:"public.json")
        attachment.name = "decision-reforge-synthetic-export.json"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
