import XCTest
@testable import YiwaiPractice

@MainActor final class LearningDemoTests: XCTestCase {
    private func path() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("personal.json") }
    private func evidence(_ model: LearningDemoModel, _ record: GameRecord, side: String = "w") throws -> GamePatternScan {
        let result = try MatePatternDetector().scan(record,side:side,at:model.decisions.now)
        try model.decisions.saveScan(result,game:record); return result
    }
    func testAuthoredSamplesExactAnswersRepeatDedupAndSideCorrection() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let personal=DecisionStore(file:file), model=try LearningDemoModel(exposureStore:personal)
        XCTAssertEqual(model.samples.count,3)
        let a=try model.importSample(model.samples[0]), b=try model.importSample(model.samples[1])
        _=try evidence(model,a); _=try evidence(model,b)
        XCTAssertTrue(model.decisions.patternSummary(games:model.game.records).repeated)
        let duplicate=try model.importSample(model.samples[0],duplicate:true); _=try evidence(model,duplicate)
        XCTAssertEqual(model.decisions.patternSummary(games:model.game.records).scans.count,2)
        _=try evidence(model,b,side:"b")
        XCTAssertFalse(model.decisions.patternSummary(games:model.game.records).repeated)
        let none=try model.importSample(model.samples[2]); XCTAssertTrue(try evidence(model,none).evidence.isEmpty)
        XCTAssertTrue(personal.data.notes.isEmpty); XCTAssertTrue(personal.data.items.isEmpty); XCTAssertNil(personal.data.scans)
    }
    func testCompleteDemoIsIsolatedAndEveryExposureProtectsPersonalNovelty() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let personal=DecisionStore(file:file), model=try LearningDemoModel(exposureStore:personal)
        let g=try model.importSample(model.samples[0]), scan=try evidence(model,g)
        let item=try model.decisions.createEvidencePlan(scan.evidence[0],game:g)
        let n=try XCTUnwrap(model.decisions.note(for:item))
        try model.decisions.appendRecollection(noteID:n.id,candidates:"Qg5",reason:"This is my reflection after seeing feedback.")
        XCTAssertThrowsError(try model.advanceToDue())
        let practice=try XCTUnwrap(model.decisions.begin(itemID:item.id,games:[g],practice:true))
        try model.decisions.submit(sessionID:practice.id,move:practice.puzzle.answers[0])
        try model.advanceToDue()
        let retest=try XCTUnwrap(model.decisions.begin(itemID:item.id,games:[g]))
        XCTAssertNotEqual(ReforgeRules.key(practice.puzzle.fen),ReforgeRules.key(retest.puzzle.fen))
        XCTAssertFalse(retest.early); XCTAssertEqual(retest.demonstration,true)
        try model.decisions.revealHint(sessionID:retest.id)
        try model.decisions.submit(sessionID:retest.id,move:retest.puzzle.answers[0])
        XCTAssertFalse(model.decisions.session(retest.id)!.countedIndependent)
        XCTAssertTrue(model.decisions.session(retest.id)!.resultLabel.contains("示例"))
        XCTAssertEqual(model.decisions.data.items[0].independentPasses,0)
        XCTAssertTrue(personal.data.sessions.isEmpty); XCTAssertTrue(personal.data.notes.isEmpty)
        XCTAssertTrue(personal.data.seen.contains(where:{$0.key == ReforgeRules.key(practice.puzzle.fen) && $0.source == "interactive-demo"}))
        let data=try TimeCapsule.build(games:model.game.records,notebook:[],appVersion:"0.4.1 demo",decisions:model.decisions.exportArchive()).encoded()
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let archive=try XCTUnwrap(decoder.decode(TimeCapsule.self,from:data).decisions)
        XCTAssertTrue(archive.clockOrigin.contains("simulated")); XCTAssertEqual(archive.notes[0].recollections?[0].context,"afterFeedback")
        XCTAssertTrue(archive.sessions.allSatisfy{$0.demonstration == true && !$0.countedIndependent})
        let personalItem=try personal.record(game:g,ply:0,candidates:"Qg7",reason:"personal",origin:.recollection,tag:.allReplies)
        let id=try XCTUnwrap(personal.data.items.first(where:{$0.decisionID == personalItem.id})?.id)
        let newPersonal=try XCTUnwrap(personal.begin(itemID:id,games:[g]))
        XCTAssertNotEqual(newPersonal.puzzle.id,practice.puzzle.id); XCTAssertNotEqual(newPersonal.puzzle.id,retest.puzzle.id)
    }
    func testRecollectionsPreserveOriginalAndPersistSkipWithExport() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file), g=GameRecord()
        let note=try store.record(game:g,ply:0,candidates:"e4",reason:"before moving",origin:.beforeMove,tag:.unconfirmed)
        let due=store.data.items[0].dueAt
        try store.appendRecollection(noteID:note.id,candidates:"",reason:"I now think differently.")
        try store.appendRecollection(noteID:note.id,candidates:"discard",reason:"discard",skipped:true)
        XCTAssertThrowsError(try store.appendRecollection(noteID:note.id,candidates:" ",reason:"\n"))
        let saved=DecisionStore(file:file).data.notes[0]
        XCTAssertEqual(saved.origin,.beforeMove); XCTAssertEqual(saved.recordedAt,note.recordedAt)
        XCTAssertEqual(saved.reason,note.reason); XCTAssertEqual(saved.candidates,note.candidates)
        XCTAssertEqual(saved.recollections?.count,2); XCTAssertEqual(saved.recollections?[1].reason,"")
        XCTAssertEqual(saved.recollections?[1].skipped,true); XCTAssertEqual(store.data.items[0].dueAt,due)
        let data=try TimeCapsule.build(games:[g],notebook:[],appVersion:"test",decisions:store.exportArchive()).encoded()
        XCTAssertTrue(String(decoding:data,as:UTF8.self).contains("I now think differently."))
    }
    func testOldArchiveWithoutRecollectionsStillLoadsAndFailureDoesNotReplaceWords() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let store=DecisionStore(file:file), note=try store.record(game:GameRecord(),ply:0,candidates:"e4",reason:"original",origin:.beforeMove,tag:.unconfirmed)
        XCTAssertNil(DecisionStore(file:file).data.notes[0].recollections)
        let bytes=try Data(contentsOf:file), backup=file.appendingPathExtension("backup")
        try FileManager.default.moveItem(at:file,to:backup); try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true)
        XCTAssertThrowsError(try store.appendRecollection(noteID:note.id,candidates:"e3",reason:"failed"))
        XCTAssertNil(store.data.notes[0].recollections); XCTAssertEqual(try Data(contentsOf:backup),bytes)
    }
    func testChangedSideInvalidatesEvenAnExistingEvidencePlan() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let model=try LearningDemoModel(exposureStore:DecisionStore(file:file)), g=try model.importSample(model.samples[0])
        let scan=try evidence(model,g); _=try model.decisions.createEvidencePlan(scan.evidence[0],game:g)
        _=try evidence(model,g,side:"b")
        XCTAssertThrowsError(try model.decisions.createEvidencePlan(scan.evidence[0],game:g))
    }
    func testExposurePersistenceFailureDoesNotExposeDemoOrWritePersonalProgress() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let personal=DecisionStore(file:file), model=try LearningDemoModel(exposureStore:personal)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:true)
        XCTAssertThrowsError(try model.importSample(model.samples[0]))
        XCTAssertTrue(model.game.records.isEmpty); XCTAssertTrue(model.sampleRecords.isEmpty)
        XCTAssertTrue(personal.data.seen.isEmpty)
    }
    func testDemoSampleValidationRejectsChangedAnswersAndCleanupRemovesOnlyDemo() throws {
        let file=path(); defer { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
        let personal=DecisionStore(file:file)
        var model:LearningDemoModel?=try LearningDemoModel(exposureStore:personal)
        let s=model!.samples[0], bad=LearningSample(id:s.id,title:s.title,pgn:s.pgn,misses:1,answers:["g6g5"],source:s.source,license:s.license)
        XCTAssertThrowsError(try model!.importSample(bad))
        _=try model!.importSample(s)
        let directory=model!.directory
        XCTAssertTrue(FileManager.default.fileExists(atPath:directory.path))
        model=nil
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:file.path))
    }
}
