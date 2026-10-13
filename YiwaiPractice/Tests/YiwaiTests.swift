import XCTest
@testable import YiwaiPractice

final class YiwaiTests: XCTestCase {
    #if DEBUG
    func testOfflineFailureInjectionRejectsURLLoading() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineTestProtocol.self]
        let session = URLSession(configuration:configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await session.data(from:URL(string:"https://offline-test.invalid/probe")!)
            XCTFail("Offline loading must fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code,.notConnectedToInternet)
        }
    }
    #endif
    func testAllNineAuthoredPositionsAndEveryReplayMove() throws {
        let engine = try ChessEngine()
        var count = 0
        for lesson in Lesson.all {
            for position in lesson.positions {
                let frames = try engine.frames(fen:position.fen,moves:position.line)
                XCTAssertEqual(frames.count,position.line.count + 1,position.id)
                XCTAssertEqual(frames[1].mate,position.isMate,position.id)
                XCTAssertTrue(frames[1].check,position.id)
                XCTAssertEqual(frames[1].replies.isEmpty,position.isMate,position.id)
                if !position.isMate { XCTAssertFalse(frames.last!.check,position.id) }
                XCTAssertEqual(frames.count,position.cues.count,position.id)
                count += 1
            }
        }
        XCTAssertEqual(count,9)
    }
    func testInitialPositionPerftAndIllegalMoves() throws {
        let engine = try ChessEngine()
        let initial = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        XCTAssertEqual(engine.perft(fen:initial,depth:1),20)
        XCTAssertEqual(engine.perft(fen:initial,depth:2),400)
        XCTAssertEqual(engine.perft(fen:initial,depth:3),8902)
        XCTAssertThrowsError(try engine.frames(fen:initial,moves:["e2e5"]))
        XCTAssertThrowsError(try engine.frames(fen:"not a FEN"))
    }
    func testDefencesAreExactlyTheExplainedMoves() throws {
        let engine = try ChessEngine()
        let expected = ["escape-b":"Kh7", "escape-c":"Kg7", "protection-a":"Kxg7", "relevance-c":"Rxg7"]
        for lesson in Lesson.all {
            for p in lesson.positions where !p.isMate {
                let frames = try engine.frames(fen:p.fen,moves:[p.move])
                XCTAssertEqual(frames[1].replies.map(\.san),[expected[p.id]!],p.id)
            }
        }
    }
    @MainActor func testNotebookPersistsRetestAndNotes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:dir) }
        let url = dir.appendingPathComponent("notebook.json")
        let book = Notebook(file:url)
        book.record("escape-a",correct:true)
        XCTAssertTrue(book.entries.isEmpty)
        book.record("escape-a",correct:false)
        book.setNote("escape-a",text:"先找逃生格")
        let reopened = Notebook(file:url)
        XCTAssertEqual(reopened.entries.count,1)
        XCTAssertEqual(reopened.entries[0].mistakes,1)
        XCTAssertEqual(reopened.entries[0].note,"先找逃生格")
        reopened.record("escape-a",correct:true)
        XCTAssertTrue(Notebook(file:url).entries[0].mastered)
        reopened.record("escape-a",correct:false)
        XCTAssertFalse(Notebook(file:url).entries[0].mastered)
        reopened.save("escape-a")
        XCTAssertEqual(reopened.entries.count,1)
        reopened.remove("escape-a")
        XCTAssertTrue(Notebook(file:url).entries.isEmpty)
    }
    @MainActor func testCorruptNotebookIsNeverOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        let bytes = Data("corrupt data".utf8)
        try bytes.write(to:url)
        let book = Notebook(file:url)
        XCTAssertNotNil(book.errorMessage)
        book.save("escape-a")
        XCTAssertEqual(try Data(contentsOf:url),bytes)
    }
}
