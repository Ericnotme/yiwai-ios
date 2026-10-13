import XCTest
@testable import YiwaiPractice

final class StockfishTests: XCTestCase {
    @MainActor func testFailureRetryAndReenterWithRealEngine() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let record = GameRecord(moves:["f2f3","e7e5","g2g4","d8h4"])
        let controller = ReviewController(record:record); controller.load()
        for _ in 0..<200 { if !controller.loading { break }; try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(controller.frames.isEmpty)
        controller.duration = 0 // Real WebKit validation failure, not a mocked engine.
        controller.analyze { _ in XCTFail("Invalid request produced a report") }
        for _ in 0..<200 { if !controller.running { break }; try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertTrue(controller.error?.contains("分析质量无效") == true)
        XCTAssertNil(controller.report)
        controller.duration = 450
        var stored = record
        controller.analyze { report in stored.reviewReport = report }
        for _ in 0..<600 { if !controller.running { break }; try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertFalse(controller.running); XCTAssertNil(controller.error)
        XCTAssertTrue(try XCTUnwrap(stored.reviewReport).matches(record))
        try JSONEncoder().encode(stored).write(to:url)
        controller.cancel()
        let reopened = ReviewController(record:try JSONDecoder().decode(GameRecord.self,from:Data(contentsOf:url)))
        reopened.load()
        for _ in 0..<200 { if !reopened.loading { break }; try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertEqual(reopened.report?.entries.count,4)
        XCTAssertNotNil(reopened.report?.white); XCTAssertNotNil(reopened.report?.black)
        reopened.cancel()
    }
    @MainActor func testCompleteNormalGameBothQualitiesAndEveryVariation() async throws {
        // Morphy's public Opera Game: a complete 33-ply game ending in mate.
        let record = GameRecord(moves:["e2e4", "e7e5", "g1f3", "d7d6", "d2d4", "c8g4", "d4e5", "g4f3", "d1f3", "d6e5", "f1c4", "g8f6", "f3b3", "d8e7", "b1c3", "c7c6", "c1g5", "b7b5", "c3b5", "c6b5", "c4b5", "b8d7", "e1c1", "a8d8", "d1d7", "d8d7", "h1d1", "e7e6", "b5d7", "f6d7", "b3b8", "d7b8", "d1d8"])
        for duration in [450,1400] {
            let engine = StockfishReviewEngine(); defer { engine.cancel() }
            let report = try await engine.analyze(record,duration:duration)
            XCTAssertTrue(report.matches(record)); XCTAssertTrue(report.gameComplete)
            XCTAssertEqual(report.entries.count,33)
            XCTAssertNotNil(report.white); XCTAssertNotNil(report.black)
            let rules = try ChessEngine()
            for entry in report.entries {
                let prefix = Array(record.moves.prefix(entry.ply-1))
                _ = try rules.frames(fen:record.initialFEN,moves:prefix+entry.bestPV)
                _ = try rules.frames(fen:record.initialFEN,moves:prefix+entry.playedPV)
                XCTAssertFalse(entry.coach.why.isEmpty)
                XCTAssertEqual(entry.bestPV.first,report.evaluations[entry.ply-1].best)
            }
        }
    }
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
