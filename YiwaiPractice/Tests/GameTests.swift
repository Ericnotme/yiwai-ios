import XCTest
@testable import YiwaiPractice

final class GameTests: XCTestCase {
    func testNormalizedWhiteAndBlackScoreLoss() {
        XCTAssertEqual(PositionScore.loss(before:.fromSideToMove(100,turn:"w"),after:.fromSideToMove(-80,turn:"b"),mover:"w"),20)
        XCTAssertEqual(PositionScore.loss(before:.fromSideToMove(100,turn:"b"),after:.fromSideToMove(-80,turn:"w"),mover:"b"),20)
        XCTAssertNil(PositionScore.loss(before:.init(kind:"mate",winner:"w",mateIn:2),after:.init(kind:"cp",cp:20),mover:"w"))
    }
    func testJavaScriptCoreSearchAndPGNBridge() throws {
        let engine = try ChessEngine(), record = GameRecord(moves:["e2e4","e7e5","g1f3","b8c6"])
        let state = try engine.game(record)
        XCTAssertEqual(state.sans,["e4","e5","Nf3","Nc6"])
        let input: [String:Any] = ["fen":record.initialFEN,"moves":record.moves]
        let answer: MoveSearch = try engine.call("search",[input,["maxDepth":3,"timeMs":1500],"native"])
        XCTAssertEqual(answer.searchID,"native"); XCTAssertEqual(answer.history,record.moves); XCTAssertEqual(answer.fen,state.frame.fen)
        XCTAssertTrue(state.frame.replies.contains { $0.code == answer.move })
        _ = try engine.frames(fen:record.initialFEN,moves:record.moves+answer.line.pv)
        struct Replay: Decodable { let fen: String; let result: String }
        let replay: Replay = try engine.call("roundtrip",[state.pgn]); XCTAssertEqual(replay.fen,state.frame.fen)
    }
    func testNativeReviewAndMateScoreTypes() throws {
        let engine = try ChessEngine()
        let answer: MoveReview = try engine.call("review",[["fen":ChessEngine.initialFEN,"moves":[]],"e2e4","native-review"])
        XCTAssertEqual(answer.best.depth,3); XCTAssertEqual(answer.played.depth,3); XCTAssertEqual(answer.played.pv.first,"e2e4"); XCTAssertNotNil(answer.loss)
        let fen = "7k/8/5KQ1/8/8/8/8/8 w - - 0 1"
        let mate: MoveSearch = try engine.call("search",[["fen":fen,"moves":[]],["maxDepth":3],"mate"])
        XCTAssertEqual(mate.line.score.kind,"mate"); XCTAssertNil(mate.line.score.cp)
        XCTAssertTrue(try engine.game(GameRecord(initialFEN:fen,moves:[mate.move])).frame.mate)
    }
    func testNativeCancellation() throws {
        let token = SearchCancellation(); token.cancel(); let engine = try ChessEngine(cancellation:token)
        XCTAssertThrowsError(try engine.call("search",[["fen":ChessEngine.initialFEN,"moves":[]],["maxDepth":5],"cancel"],as:MoveSearch.self))
    }
    @MainActor func testUndoAndNewGameRejectLateResults() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let controller = GameController(file:url)
        controller.newGame(human:"w",level:2); controller.play("e2e4"); XCTAssertTrue(controller.thinking)
        controller.undo(); XCTAssertEqual(controller.current?.moves,[]); XCTAssertEqual(controller.snapshot?.frame.fen,ChessEngine.initialFEN)
        controller.play("d2d4"); controller.newGame(human:"w",level:0); let id = controller.currentID
        try await Task.sleep(for:.seconds(2.3))
        XCTAssertEqual(controller.currentID,id); XCTAssertEqual(controller.current?.moves,[]); XCTAssertFalse(controller.thinking)
        controller.play("e2e4"); controller.pause(); try await Task.sleep(for:.seconds(0.6))
        XCTAssertEqual(controller.current?.moves,["e2e4"]); XCTAssertTrue(controller.paused)
        XCTAssertEqual(GameController(file:url).current?.moves,["e2e4"])
    }
    @MainActor func testAIReplyUndoAndBlackStart() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let controller = GameController(file:url)
        controller.newGame(human:"w",level:0); controller.play("e2e4")
        for _ in 0..<40 { if !controller.thinking { break }; try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertEqual(controller.current?.moves.count,2); controller.undo(); XCTAssertEqual(controller.current?.moves,[])
        controller.newGame(human:"b",level:0)
        for _ in 0..<40 { if !controller.thinking { break }; try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertEqual(controller.current?.moves.count,1); XCTAssertTrue(controller.canMove); XCTAssertFalse(controller.canUndo)
        controller.undo(); XCTAssertEqual(controller.current?.moves.count,1); controller.pause()
    }
    @MainActor func testCorruptStorePreserved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let data = Data("broken".utf8); try data.write(to:url)
        let controller = GameController(file:url); controller.newGame(human:"w",level:0)
        XCTAssertNotNil(controller.errorMessage); XCTAssertEqual(try Data(contentsOf:url),data)
    }
    @MainActor func testAnalysisCannotAttachToChangedHistory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let controller = GameController(file:url)
        controller.newGame(human:"w",level:0); controller.play("e2e4"); controller.pause()
        let original = try XCTUnwrap(controller.current)
        let answer: MoveReview = try ChessEngine().call("review",[["fen":original.initialFEN,"moves":[]],"e2e4","saved"])
        controller.saveAnalysis(answer,ply:0,record:original)
        XCTAssertEqual(controller.current?.analyses.count,1)
        controller.undo(); controller.saveAnalysis(answer,ply:0,record:original)
        XCTAssertEqual(controller.current?.analyses.count,0)
        XCTAssertEqual(controller.current?.moves,[])
    }
    @MainActor func testReviewCancelAndResumeKeepsUnanalysedStepsUnknown() async throws {
        let record = GameRecord(moves:["e2e4","e7e5","g1f3","b8c6"])
        let review = ReviewController(record:record); review.load()
        for _ in 0..<50 { if !review.loading { break }; try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertNil(review.error); XCTAssertEqual(review.frames.count,5)
        review.analyze { _ in }; review.cancel()
        try await Task.sleep(for:.milliseconds(400))
        XCTAssertFalse(review.running); XCTAssertTrue(review.results.isEmpty)
        review.analyze { _ in }
        for _ in 0..<150 { if !review.running { break }; try await Task.sleep(for:.milliseconds(100)) }
        XCTAssertEqual(review.results.count,4); XCTAssertTrue(review.failures.isEmpty)
        review.cancel()
    }
}
