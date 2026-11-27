import Foundation
import Combine

struct LearningSample: Codable, Identifiable {
    let id: String; let title: String; let pgn: String
    let misses: Int; let answers: [String]; let source: String; let license: String
    static func bundled() throws -> [Self] {
        guard let url = Bundle.main.url(forResource:"learning-demo",withExtension:"json") else { throw ChessFailure.invalid("示例资源不可用。") }
        return try JSONDecoder().decode([Self].self,from:Data(contentsOf:url))
    }
}
private final class DemoClock {
    var offset: TimeInterval = 0
    var now: Date { Date().addingTimeInterval(offset) }
}
@MainActor final class LearningDemoModel: ObservableObject, Identifiable {
    let id = UUID()
    let game: GameController
    let decisions: DecisionStore
    let notebook: Notebook
    let samples: [LearningSample]
    let directory: URL
    @Published private(set) var sampleRecords: [String:UUID] = [:]
    @Published private(set) var advanced = false
    private let demoClock: DemoClock
    private let exposureStore: DecisionStore
    init(exposureStore: DecisionStore) throws {
        self.exposureStore = exposureStore
        samples = try LearningSample.bundled()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("yiwai-demo-\(UUID().uuidString)")
        let clock = DemoClock(); demoClock = clock
        game = GameController(file:directory.appendingPathComponent("games.json"))
        notebook = Notebook(file:directory.appendingPathComponent("notebook.json"))
        decisions = DecisionStore(file:directory.appendingPathComponent("decisions.json"),clock:{clock.now},clockOrigin:"interactive demo; simulated due time; not personal learning evidence",demonstration:true,exposureRecorder:{ exposure in
            var realExposure = exposure
            realExposure = ReforgeSeen(key:exposure.key,puzzleID:exposure.puzzleID,version:exposure.version,at:Date(),source:"interactive-demo")
            try exposureStore.recordExposure(realExposure)
        })
    }
    deinit { try? FileManager.default.removeItem(at:directory) }
    @discardableResult func importSample(_ sample: LearningSample, duplicate: Bool = false) throws -> GameRecord {
        if !duplicate, let id = sampleRecords[sample.id], let saved = game.records.first(where:{$0.id == id}) { return saved }
        struct Imported: Decodable { let initialFen: String; let moves: [String] }
        let engine = try ChessEngine(), parsed: Imported = try engine.call("importPosition",[sample.pgn,"pgn"])
        let candidate = GameRecord(initialFEN:parsed.initialFen,moves:parsed.moves)
        let checked = try MatePatternDetector().scan(candidate,side:"w",at:decisions.now)
        guard checked.misses == sample.misses, checked.evidence.flatMap(\.answers).sorted() == sample.answers.sorted(),
              !sample.source.isEmpty, !sample.license.isEmpty else { throw ChessFailure.invalid("示例未通过棋规核验，暂不提供。") }
        // Record every displayed sample position before exposing it, including its played continuation.
        for frame in try engine.frames(fen:parsed.initialFen,moves:parsed.moves) {
            try exposureStore.recordExposure(.init(key:ReforgeRules.key(frame.fen),puzzleID:"demo-\(sample.id)",version:1,at:Date(),source:"interactive-demo"))
        }
        let record = try game.importPosition(sample.pgn,format:"pgn")
        if !duplicate { sampleRecords[sample.id] = record.id }
        return record
    }
    func advanceToDue() throws {
        guard decisions.data.sessions.contains(where:{$0.kind == "practice" && $0.finished}),
              decisions.data.sessions.allSatisfy(\.finished), let due = decisions.data.items.map(\.dueAt).min(), due > decisions.now else {
            throw ChessFailure.invalid("先完成或跳过示例针对性练习，再模拟下一次到期。")
        }
        demoClock.offset += due.timeIntervalSince(decisions.now) + 1
        decisions.objectWillChange.send(); advanced = true
    }
}
