import XCTest
@testable import YiwaiPractice

final class ReviewCacheTests: XCTestCase {
    // Deterministically generated legal game, not a user's saved game. Synthetic
    // scores exercise cache lifecycle only; real Stockfish accuracy has separate tests.
    static let moves = ["e2e3","b7b5","b2b3","e7e5","e1e2","d8f6","d2d3","b8a6","e2d2","f6d8","d2c3","g7g6","e3e4","a6b8","c1a3","a7a5","f2f4","f8h6","a3c5","d8h4","d1e2","h4f4","a2a3","h6g5","h2h4","f4f1","e2d1","d7d5","d1e2","f7f5","c5b4","d5d4","c3b2","f1f4","b1d2","f5e4","b4d6","g8h6","d2b1","f4h2","e2f1","h2g2","h4h5","g2e2","f1e2","a8a6","b1d2","g5e3","b2a2","e3d2","e2f2","b8d7","c2c4","d7b6","d6b4","b6a8","g1e2","h8g8","h1h3","a5a4","c4c5","d2c1","f2f1","a6f6","e2c1","f6d6","f1e1","h6g4","h3f3","g6g5","h5h6","g4f2","a2b2","c8f5","e1f1","d6a6","b4e1","f2g4","f3g3","g4e3","b2b1","f5d7","b3b4","a6d6","c5d6","c7c5","g3g1","e3f1","b4c5","g8g6","c5c6","f1e3","c1e2","g6e6","b1b2","a8c7","c6d7","e8d8","e2c1","e3d5","d6c7","d5c7","a1a2","e6a6","e1g3","a6e6","g1e1","e6d6","b2c2","d6d7","c2d2","d7d6","e1e4","g5g4","e4g4","c7e8","a2c2","e5e4","g4g8","d6b6"]

    func cachedRecord(duration: Int) throws -> GameRecord {
        var record = GameRecord(moves:Self.moves,ending:"saved")
        let frames = try ChessEngine().frames(fen:record.initialFEN,moves:record.moves)
        let evaluations = frames.enumerated().map { i,frame in
            let best = i < record.moves.count ? record.moves[i] : frame.replies.first!.code
            return ReviewEvaluation(cp:0,win:50,depth:1,terminal:false,draw:false,mate:nil,winner:nil,best:best,pv:[best],nodes:1,legalCount:frame.replies.count)
        }
        let entries = record.moves.enumerated().map { i,move in
            let san = frames[i+1].san
            let coach = CoachExplanation(theme:"测试",summary:"缓存测试",why:"合法变化",missed:"合法变化",habit:"检查应手",boundary:"合成测试分值",bestSAN:[san],playedSAN:[san])
            return ReviewedMove(ply:i+1,color:frames[i].turn,san:san,number:i/2+1,loss:0,rawLoss:0,accuracy:100,weight:1,category:"best",forced:false,bestPV:[move],playedPV:[move],coach:coach)
        }
        record.reviewReport = GameReviewReport(metric:GameReviewReport.metricID,engine:GameReviewReport.engineName,initialFEN:record.initialFEN,history:record.moves,duration:duration,gameComplete:false,evaluations:evaluations,entries:entries,white:100,black:100,minDepth:1,maxDepth:1)
        return record
    }
    @MainActor func waitForLoad(_ controller: ReviewController, timeout: Double = 5) async throws {
        let end = Date().addingTimeInterval(timeout)
        while controller.loading, Date() < end { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertFalse(controller.loading,"Long cached report did not load within the bounded budget")
        XCTAssertNil(controller.error)
    }
    @MainActor func testBothCachedQualitiesColdReadAndRepeatedEntryPreserveFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        for duration in [450,1400] {
            let data = try JSONEncoder().encode([cachedRecord(duration:duration)])
            try data.write(to:url)
            for _ in 0..<3 {
                let game = GameController(file:url), record = try XCTUnwrap(game.current)
                let controller = ReviewController(record:record)
                for _ in 0..<20 { controller.load() }
                try await waitForLoad(controller)
                XCTAssertEqual(controller.report?.history,Self.moves)
                XCTAssertEqual(controller.duration,duration)
                XCTAssertEqual(controller.frames.count,Self.moves.count+1)
                controller.cancel(); controller.load()
                XCTAssertFalse(controller.loading)
                XCTAssertEqual(controller.report?.entries.count,Self.moves.count)
                XCTAssertEqual(try Data(contentsOf:url),data,"Read must not rewrite saved game data")
            }
        }
    }
    @MainActor func testRapidLeaveAndReenterCancelsOldLoadsWithoutStalePublication() async throws {
        let record = try cachedRecord(duration:1400)
        var cancelled: [ReviewController] = []
        for _ in 0..<12 {
            let controller = ReviewController(record:record)
            controller.load(); controller.cancel(); cancelled.append(controller)
        }
        let resumed = cancelled[0]
        resumed.load(); try await waitForLoad(resumed)
        XCTAssertEqual(resumed.report?.duration,1400)
        for controller in cancelled.dropFirst() {
            XCTAssertNil(controller.report); XCTAssertTrue(controller.frames.isEmpty); XCTAssertNil(controller.error)
        }
    }
    @MainActor func testIllegalCachedLineIsRejectedWithoutDestroyingSavedGame() async throws {
        let original = try cachedRecord(duration:450)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        var report = object["reviewReport"] as! [String:Any], entries = report["entries"] as! [[String:Any]]
        entries[60]["bestPV"] = ["e2e5"]; report["entries"] = entries; object["reviewReport"] = report
        let record = try JSONDecoder().decode(GameRecord.self,from:JSONSerialization.data(withJSONObject:object))
        let controller = ReviewController(record:record); controller.load(); try await waitForLoad(controller)
        XCTAssertNil(controller.report); XCTAssertEqual(controller.frames.count,121)
        XCTAssertEqual(controller.record.moves,original.moves); XCTAssertNotNil(controller.record.reviewReport)
    }
}
