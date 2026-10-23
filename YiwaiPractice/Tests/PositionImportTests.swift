import XCTest
@testable import YiwaiPractice

final class PositionImportTests: XCTestCase {
    @MainActor func testFENImportPersistenceAndFailedImportKeepsGame() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let game = GameController(file:url)
        game.newGame(human:"w",level:0)
        let original = game.currentID
        let fen = "7k/8/8/3pP3/8/8/8/K7 w - d6 0 12"
        let imported = try game.importPosition(fen,format:"fen")
        XCTAssertEqual(imported.initialFEN,fen)
        XCTAssertEqual(game.currentID,original)
        XCTAssertTrue(imported.moves.isEmpty)
        XCTAssertEqual(imported.source,"fen")
        let engine = try ChessEngine()
        let state = try engine.game(imported)
        XCTAssertTrue(state.frame.replies.contains { $0.code == "e5d6" })
        XCTAssertTrue(state.pgn.contains("[FEN \"\(fen)\"]"))
        let count = game.records.count
        XCTAssertThrowsError(try game.importPosition("8/8/8/8/8/8/4k3/4K3 w - - 0 1",format:"fen"))
        XCTAssertThrowsError(try game.importPosition("7k/8/8/3pP3/8/8/8/K7 w K d6 0 12",format:"fen"))
        XCTAssertEqual(game.records.count,count)
        XCTAssertEqual(game.currentID,original)
        game.resume(imported.id)
        XCTAssertEqual(game.currentID,original)
        let reopened = GameController(file:url)
        XCTAssertEqual(reopened.records.first?.initialFEN,fen)
        XCTAssertEqual(reopened.currentID,original)
    }

    @MainActor func testPGNImportAndOldRecordCompatibility() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let game = GameController(file:url)
        let record = try game.importPosition("[White \"Alice\"]\n[Black \"Bob\"]\n\n1. e4 e5 2. Nf3 Nc6 *",format:"pgn")
        XCTAssertEqual(record.moves,["e2e4","e7e5","g1f3","b8c6"])
        XCTAssertEqual(record.importedHeaders?["White"],"Alice")
        XCTAssertTrue(try ChessEngine().game(record).pgn.contains("[Black \"Bob\"]"))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
        old.removeValue(forKey:"source"); old.removeValue(forKey:"importedHeaders")
        XCTAssertNil(try JSONDecoder().decode(GameRecord.self,from:JSONSerialization.data(withJSONObject:old)).source)
    }

    @MainActor func testRealStockfishStandalonePositionAndLegalVariation() async throws {
        let record = GameRecord(initialFEN:"7k/8/5KQ1/8/8/8/8/8 w - - 0 1",source:"fen")
        let engine = StockfishReviewEngine()
        defer { engine.cancel() }
        let report = try await engine.analyze(record,duration:450)
        XCTAssertTrue(report.matches(record))
        XCTAssertEqual(report.evaluations.count,1)
        XCTAssertEqual(report.entries.count,0)
        XCTAssertNil(report.white); XCTAssertNil(report.black)
        let value = try XCTUnwrap(report.evaluations.first)
        XCTAssertEqual(value.winner,"w")
        XCTAssertNotNil(value.mate)
        let frames = try ChessEngine().frames(fen:record.initialFEN,moves:value.pv)
        XCTAssertTrue(frames.last?.mate == true)
    }
}
