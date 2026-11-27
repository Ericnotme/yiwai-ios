import XCTest
@testable import YiwaiPractice

final class FortressLabTests: XCTestCase {
    func testThreeConditionsUseBundledRules() throws {
        let engine = try ChessEngine()
        for question in FortressQuestion.examples {
            let frame = try XCTUnwrap(engine.frames(fen: question.fen).last)
            XCTAssertEqual(question.answer(using: frame), question.expected)
        }
    }
    func testEveryFirstMoveInThreeSeeds() throws {
        let engine = try ChessEngine()
        let replay: FortressSession<ChessFrame>.Replay = { fen, moves in
            try XCTUnwrap(engine.frames(fen: fen, moves: moves).last)
        }
        for seed in FortressPolicy.seeds.indices {
            let root = try FortressSession(seed: seed, replay: replay)
            for move in root.current.frame.replies {
                var session = root
                try session.play(move.code, replay: replay)
                XCTAssertTrue(["*", "1/2-1/2"].contains(session.current.frame.result))
                XCTAssertEqual(session.current.moves.first, move.code)
                session.undo()
                XCTAssertEqual(session.current.moves, [])
                XCTAssertEqual(session.current.frame.fen, root.current.frame.fen)
            }
        }
    }
    func testAllPromotionsAndTerminalUndo() throws {
        let engine = try ChessEngine()
        let replay: FortressSession<ChessFrame>.Replay = { fen, moves in
            try XCTUnwrap(engine.frames(fen: fen, moves: moves).last)
        }
        for p in ["q", "r", "b", "n"] {
            var session = try FortressSession(seed: 0, replay: replay)
            try session.play("a7a8" + p, replay: replay)
            XCTAssertEqual(session.current.moves, ["a7a8" + p, "b7a8"])
            XCTAssertEqual(session.current.frame.result, "1/2-1/2")
            XCTAssertFalse(session.canMove)
            XCTAssertThrowsError(try session.play("e6e5", replay: replay))
            session.undo()
            XCTAssertTrue(session.canMove)
            try session.play("a7a8" + p, replay: replay)
            session.restart()
            XCTAssertTrue(session.current.moves.isEmpty)
        }
    }
    func testBadMoveRollsBack() throws {
        let engine = try ChessEngine()
        let replay: FortressSession<ChessFrame>.Replay = { fen, moves in
            try XCTUnwrap(engine.frames(fen: fen, moves: moves).last)
        }
        var session = try FortressSession(seed: 0, replay: replay)
        let root = session.current.frame.fen
        XCTAssertThrowsError(try session.play("a7a6", replay: replay))
        XCTAssertEqual(session.current.frame.fen, root)
        let unavailable: FortressSession<ChessFrame>.Replay = { _, _ in throw FortressSessionError.invalidReply }
        XCTAssertThrowsError(try session.play("a7a8q", replay: unavailable))
        XCTAssertEqual(session.current.frame.fen, root)
        XCTAssertTrue(session.current.moves.isEmpty)
    }
}
