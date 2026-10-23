import XCTest
@testable import YiwaiPractice

final class TimeCapsuleTests: XCTestCase {
    private let pgn = "[Event \"Local test\"]\r\n[White \"Example A\"]\r\n[Black \"Example B\"]\r\n\r\n1. e4 {先看对手的威胁 ♞} (1. d4 d5) e5 2. Nf3 Nc6 *\r\n"

    @MainActor func testRawPGNNoteAndFENSurviveRelaunchAndExport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let file = dir.appendingPathComponent("games.json"), bookFile = dir.appendingPathComponent("notebook.json")
        let game = GameController(file:file), book = Notebook(file:bookFile)
        game.newGame(human:"w",level:0); game.pause()
        let imported = try game.importPosition(pgn,format:"pgn")
        let note = "  今天为什么走马？\nKeep the question. ♞\n"
        try game.savePersonalNote(imported.id,text:note)
        let fen = "7k/8/8/3pP3/8/8/8/K7 w - d6 0 12"
        let position = try game.importPosition(fen,format:"fen")
        book.record("escape-a",correct:false); book.setNote("escape-a",text:"检查所有应将")
        let reopened = GameController(file:file), reopenedBook = Notebook(file:bookFile)
        XCTAssertEqual(reopened.records.first(where:{$0.id == imported.id})?.originalPGN,pgn)
        XCTAssertEqual(reopened.records.first(where:{$0.id == imported.id})?.personalNote,note)
        let originalGameFile = try Data(contentsOf:file), originalBookFile = try Data(contentsOf:bookFile)
        let capsule = try TimeCapsule.build(games:reopened.capsuleRecords(),notebook:reopenedBook.capsuleEntries(),appVersion:"test")
        let data = try capsule.encoded(), decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let attachment = XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
        attachment.name = "sample-time-capsule-synthetic-only.json"; attachment.lifetime = .keepAlways; add(attachment)
        let decoded = try decoder.decode(TimeCapsule.self,from:data)
        XCTAssertEqual(decoded.format,"yiwai-local-time-capsule"); XCTAssertEqual(decoded.schemaVersion,2)
        XCTAssertEqual(decoded.games.count,3); XCTAssertEqual(decoded.gamePGN.count,3)
        XCTAssertEqual(decoded.games.first(where:{$0.id == imported.id})?.originalPGN,pgn)
        XCTAssertEqual(decoded.games.first(where:{$0.id == imported.id})?.personalNote,note)
        XCTAssertEqual(decoded.notebook.first?.note,"检查所有应将")
        XCTAssertEqual(decoded.notebook.first?.attempts,1)
        XCTAssertEqual(decoded.lessons.flatMap(\.positions).count,9)
        XCTAssertTrue(decoded.lessons.flatMap(\.positions).contains(where:{$0.id == decoded.notebook.first?.id}))
        for export in decoded.gamePGN {
            let record = try XCTUnwrap(decoded.games.first(where:{$0.id == export.recordID}))
            struct Imported: Decodable { let initialFen: String; let moves: [String] }
            let parsed: Imported = try ChessEngine().call("importPosition",[export.mainlinePGN,"pgn"])
            XCTAssertEqual(parsed.initialFen,record.initialFEN); XCTAssertEqual(parsed.moves,record.moves)
        }
        XCTAssertEqual(decoded.games.first(where:{$0.id == position.id})?.initialFEN,fen)
        XCTAssertEqual(try Data(contentsOf:file),originalGameFile)
        XCTAssertEqual(try Data(contentsOf:bookFile),originalBookFile)
    }

    func testExportPreservesSavedReviewAndAllMetadata() throws {
        var record = try ReviewCacheTests().cachedRecord(duration:1400)
        record.personalNote = "合成测试记录"; record.importedHeaders = ["Event":"Synthetic fixture"]
        let capsule = try TimeCapsule.build(games:[record],notebook:[],appVersion:"test")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(TimeCapsule.self,from:capsule.encoded())
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys; encoder.dateEncodingStrategy = .secondsSince1970
        XCTAssertEqual(try encoder.encode(decoded.games),try encoder.encode([record]))
    }

    @MainActor func testOldOptionalFieldsRemainCompatible() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(GameRecord(moves:["e2e4"]))) as? [String:Any])
        for key in ["source","importedHeaders","originalPGN","personalNote"] { object.removeValue(forKey:key) }
        let old = try JSONDecoder().decode(GameRecord.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(old.originalPGN); XCTAssertNil(old.personalNote)
        XCTAssertEqual(old.moves,["e2e4"])
        let capsule = try TimeCapsule.build(games:[old],notebook:[],appVersion:"test")
        XCTAssertNil(capsule.games[0].originalPGN)
        XCTAssertTrue(capsule.gamePGN[0].mainlinePGN.contains("e4"))
    }

    @MainActor func testFailedWritesDoNotCommitImportOrNote() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let file = dir.appendingPathComponent("games.json"), backup = dir.appendingPathComponent("saved.json")
        let game = GameController(file:file), record = try game.importPosition(pgn,format:"pgn")
        try game.savePersonalNote(record.id,text:"saved")
        let original = try Data(contentsOf:file)
        try FileManager.default.moveItem(at:file,to:backup)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true)
        XCTAssertThrowsError(try game.savePersonalNote(record.id,text:"must not appear saved"))
        XCTAssertEqual(game.records[0].personalNote,"saved")
        XCTAssertThrowsError(try game.importPosition(pgn,format:"pgn"))
        XCTAssertEqual(game.records.count,1)
        XCTAssertEqual(try Data(contentsOf:backup),original)
        try FileManager.default.removeItem(at:file); try FileManager.default.moveItem(at:backup,to:file)
        try game.savePersonalNote(record.id,text:"retry works")
        XCTAssertEqual(GameController(file:file).records[0].personalNote,"retry works")
    }

    @MainActor func testCorruptionBlocksIncompleteExportAndLeavesOriginals() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let original = Data("not-json".utf8); try original.write(to:file)
        XCTAssertThrowsError(try GameController(file:file).capsuleRecords())
        XCTAssertThrowsError(try Notebook(file:file).capsuleEntries())
        XCTAssertEqual(try Data(contentsOf:file),original)
    }

    @MainActor func testLimitsRejectWithoutTruncatingSavedContent() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let game = GameController(file:file), record = try game.importPosition(pgn,format:"pgn")
        let fullNote = String(repeating:"棋",count:10000)
        try game.savePersonalNote(record.id,text:fullNote)
        XCTAssertThrowsError(try game.savePersonalNote(record.id,text:fullNote+"多"))
        XCTAssertEqual(game.records[0].personalNote,fullNote)
        XCTAssertThrowsError(try game.importPosition("1. e4 {"+String(repeating:"棋",count:70000)+"} *",format:"pgn"))
        XCTAssertEqual(game.records.count,1)
    }

    func testEmptyCapsuleAndInvalidHistoryAreExplicit() throws {
        let capsule = try TimeCapsule.build(games:[],notebook:[],appVersion:"test")
        XCTAssertTrue(capsule.games.isEmpty); XCTAssertTrue(capsule.gamePGN.isEmpty)
        XCTAssertEqual(capsule.lessons.count,3)
        XCTAssertThrowsError(try TimeCapsule.build(games:[GameRecord(moves:["e2e5"])],notebook:[],appVersion:"test"))
    }
}
