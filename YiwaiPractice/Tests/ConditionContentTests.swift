import XCTest
@testable import YiwaiPractice

final class ConditionContentTests:XCTestCase {
    func testAllProofsAndCompleteMateAnswerSets() throws {
        let catalog=try ConditionCatalog.bundled(), rules=try ConditionRules()
        XCTAssertEqual(catalog.positions.count,16); XCTAssertEqual(catalog.families.count,3)
        for p in catalog.positions { try rules.validate(p,requireEngine:false) }
        XCTAssertEqual(Set(catalog.positions.map{ReforgeRules.key($0.fen)}).count,16)
    }
    @MainActor func testEveryPositionWithBundledStockfish() async throws {
        let catalog=try ConditionCatalog.bundled(), rules=try ConditionRules()
        var checks:[ConditionEngineCheck]=[]
        for p in catalog.positions {
            try rules.validate(p,requireEngine:false)
            let engine=StockfishReviewEngine()
            let report:GameReviewReport
            do { report=try await engine.analyze(GameRecord(initialFEN:p.fen,source:"fen"),duration:1400) }
            catch { engine.cancel();throw error };engine.cancel()
            let v=try XCTUnwrap(report.evaluations.first)
            let check=ConditionEngineCheck(id:p.id,digest:p.digest,engine:report.engine,checkedAt:ISO8601DateFormatter().string(from:Date()),best:v.best,mate:v.mate,winner:v.winner,depth:v.depth,pv:v.pv)
            try rules.validate(p,check:check); checks.append(check)
        }
        let data=try JSONEncoder().encode(checks)
        let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json");attachment.name="condition-engine-verification.json";attachment.lifetime = .keepAlways;add(attachment)
        XCTAssertEqual(checks.count,16)
    }
}
