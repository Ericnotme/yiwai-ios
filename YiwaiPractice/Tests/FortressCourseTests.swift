import XCTest
@testable import YiwaiPractice

final class FortressCourseTests: XCTestCase {
    func testEveryCourseCandidateAndEvidenceUsesBundledRules() throws {
        let course = try FortressCourseCatalog.load(), engine = try ChessEngine()
        XCTAssertEqual(course.chapters.count,4); XCTAssertEqual(course.questions.count,16)
        try course.validate(using:engine)
        XCTAssertEqual(Set(course.questions.map(\.id)).count,16)
        for question in course.questions {
            let result = try FortressCourseEvaluation(question:question,engine:engine)
            XCTAssertEqual(result.candidateIsLegal,question.expectedLegal,question.id)
            XCTAssertNotEqual(result.before.fen,result.after.fen,question.id)
            if result.candidateIsLegal { XCTAssertEqual(result.evidenceMove.code,question.candidateUCI) }
            else {
                XCTAssertNotEqual(result.evidenceMove.code,question.candidateUCI)
                XCTAssertThrowsError(try engine.frames(fen:question.fen,moves:[question.candidateUCI]))
            }
        }
    }

    @MainActor func testFirstAnswerSurvivesRetryRelaunchAndCompleteExport() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let course=try FortressCourseCatalog.load(), question=course.questions[0]
        let first=Date(timeIntervalSince1970:100), later=Date(timeIntervalSince1970:200)
        let store=FortressProgressStore(file:file,clock:{first})
        try store.record(question:question,version:course.version,choice:false,legalAnswer:true)
        let reopened=FortressProgressStore(file:file,clock:{later})
        try reopened.record(question:question,version:course.version,choice:true,legalAnswer:true)
        let row=try XCTUnwrap(FortressProgressStore(file:file).entry(for:question,version:course.version))
        XCTAssertFalse(row.firstAnswer.choice); XCTAssertFalse(row.firstAnswer.correct)
        XCTAssertEqual(row.firstAnswer.at,first); XCTAssertTrue(row.latestAnswer.correct)
        XCTAssertEqual(row.latestAnswer.at,later); XCTAssertEqual(row.attempts,2)
        XCTAssertEqual(row.question,question)
        let bytes=try Data(contentsOf:file)
        let capsule=try TimeCapsule.build(games:[],notebook:[],appVersion:"0.4.4 (16)",fortressProgress:reopened.exportArchive(),fortressLessons:course)
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let copy=try decoder.decode(TimeCapsule.self,from:capsule.encoded())
        XCTAssertEqual(copy.schemaVersion,6); XCTAssertEqual(copy.fortressProgress?.records,[row])
        XCTAssertEqual(copy.fortressLessons,course)
        XCTAssertEqual(try Data(contentsOf:file),bytes)
    }

    @MainActor func testCorruptMissingOrChangedFilesCannotBeOverwrittenOrExported() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let question=try FortressCourseCatalog.load().questions[0]
        let original=Data("unreadable original".utf8); try original.write(to:file)
        let corrupt=FortressProgressStore(file:file)
        XCTAssertNotNil(corrupt.errorMessage)
        XCTAssertThrowsError(try corrupt.record(question:question,version:1,choice:true,legalAnswer:true))
        XCTAssertThrowsError(try corrupt.exportArchive())
        XCTAssertEqual(try Data(contentsOf:file),original)
        try FileManager.default.removeItem(at:file)
        let valid=FortressProgressStore(file:file)
        try valid.record(question:question,version:1,choice:true,legalAnswer:true)
        try FileManager.default.removeItem(at:file)
        XCTAssertThrowsError(try valid.exportArchive())
        XCTAssertThrowsError(try valid.record(question:question,version:1,choice:false,legalAnswer:true))
        XCTAssertFalse(FileManager.default.fileExists(atPath:file.path))
    }

    @MainActor func testSaveFailureDoesNotCommitProgressAndBlocksIncompleteExport() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let file=directory.appendingPathComponent("progress.json"), saved=directory.appendingPathComponent("preserved.json")
        let question=try FortressCourseCatalog.load().questions[0], store=FortressProgressStore(file:file)
        try store.record(question:question,version:1,choice:false,legalAnswer:true)
        let original=try Data(contentsOf:file)
        try FileManager.default.moveItem(at:file,to:saved)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true)
        XCTAssertThrowsError(try store.record(question:question,version:1,choice:true,legalAnswer:true))
        XCTAssertThrowsError(try store.exportArchive())
        XCTAssertEqual(store.data.records.first?.attempts,1)
        XCTAssertEqual(try Data(contentsOf:saved),original)
    }

    @MainActor func testChangedQuestionCannotOverwriteFirstAnswerUnderSameVersion() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:file) }
        let q=try FortressCourseCatalog.load().questions[0], store=FortressProgressStore(file:file)
        try store.record(question:q,version:1,choice:true,legalAnswer:q.expectedLegal)
        let changed=FortressCourseQuestion(id:q.id,title:q.title,prompt:q.prompt+"（修订）",fen:q.fen,candidateUCI:q.candidateUCI,highlight:q.highlight,explanation:q.explanation,expectedLegal:q.expectedLegal)
        let original=try Data(contentsOf:file)
        XCTAssertThrowsError(try store.record(question:changed,version:1,choice:false,legalAnswer:q.expectedLegal))
        XCTAssertEqual(try Data(contentsOf:file),original)
        try store.record(question:changed,version:2,choice:false,legalAnswer:q.expectedLegal)
        XCTAssertEqual(store.data.records.count,2)
        XCTAssertEqual(store.entry(for:q,version:1)?.firstAnswer.choice,true)
        XCTAssertEqual(store.entry(for:changed,version:2)?.firstAnswer.choice,false)
    }

    func testSchemaFourStillDecodesWithoutInventingFortressRecords() throws {
        let capsule=try TimeCapsule.build(games:[GameRecord(moves:["e2e4"])],notebook:[],appVersion:"legacy")
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:capsule.encoded()) as? [String:Any])
        old["schemaVersion"]=4; old.removeValue(forKey:"fortressProgress");old.removeValue(forKey:"fortressLessons")
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .secondsSince1970
        let restored=try decoder.decode(TimeCapsule.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertEqual(restored.schemaVersion,4);XCTAssertEqual(restored.games.first?.moves,["e2e4"])
        XCTAssertNil(restored.fortressProgress);XCTAssertNil(restored.fortressLessons)
    }
}
