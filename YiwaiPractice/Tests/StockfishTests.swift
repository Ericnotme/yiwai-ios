import XCTest
@testable import YiwaiPractice

final class StockfishTests: XCTestCase {
    @MainActor func testRealStockfishMateReportAndEveryVariation() async throws {
        let record = GameRecord(moves:["f2f3","e7e5","g2g4","d8h4"])
        let engine = StockfishReviewEngine(); defer { engine.cancel() }
        let report = try await engine.analyze(record,duration:450)
        XCTAssertTrue(report.matches(record)); XCTAssertTrue(report.gameComplete)
        XCTAssertEqual(report.evaluations.last?.mate,0); XCTAssertEqual(report.evaluations.last?.winner,"b")
        XCTAssertNotNil(report.white); XCTAssertNotNil(report.black); XCTAssertGreaterThan(report.minDepth,0)
        for entry in report.entries {
            let prefix = Array(record.moves.prefix(entry.ply-1)), rules = try ChessEngine()
            XCTAssertFalse(entry.coach.why.isEmpty); XCTAssertFalse(entry.coach.missed.isEmpty)
            _ = try rules.frames(fen:record.initialFEN,moves:prefix+entry.bestPV)
            _ = try rules.frames(fen:record.initialFEN,moves:prefix+entry.playedPV)
        }
    }
    @MainActor func testReportPersistsButCannotAttachAfterUndo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let game = GameController(file:url); game.newGame(human:"w",level:0); game.play("e2e4"); game.pause()
        let record = try XCTUnwrap(game.current), engine = StockfishReviewEngine(); defer { engine.cancel() }
        let report = try await engine.analyze(record,duration:450)
        game.saveReview(report,record:record)
        XCTAssertEqual(GameController(file:url).current?.reviewReport?.history,record.moves)
        game.undo(); game.saveReview(report,record:record)
        XCTAssertNil(game.current?.reviewReport)
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(report)) as? [String:Any])
        dictionary["engine"] = "Seed 0.2"
        let foreign = try JSONDecoder().decode(GameReviewReport.self,from:JSONSerialization.data(withJSONObject:dictionary))
        XCTAssertFalse(foreign.matches(record))
    }
    @MainActor func testInFlightCancellationNeverReturnsReport() async throws {
        let engine = StockfishReviewEngine()
        let task = Task { try await engine.analyze(GameRecord(moves:["e2e4","e7e5","g1f3","b8c6"]),duration:1400) }
        try await Task.sleep(for:.milliseconds(200)); engine.cancel()
        do { _ = try await task.value; XCTFail("Cancelled work produced a report") } catch {}
    }
    func testOldRecordWithoutReportStillDecodes() throws {
        let data = try JSONEncoder().encode(GameRecord(moves:["e2e4"]))
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        dictionary.removeValue(forKey:"reviewReport")
        let old = try JSONDecoder().decode(GameRecord.self,from:JSONSerialization.data(withJSONObject:dictionary))
        XCTAssertNil(old.reviewReport); XCTAssertEqual(old.moves,["e2e4"])
    }
}
