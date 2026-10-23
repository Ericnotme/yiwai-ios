import Foundation
import Combine

enum DecisionTag: String, Codable, CaseIterable {
    case unconfirmed, allReplies
    var title: String { self == .allReplies ? "将军后检查全部合法应将" : "暂不归类 / 不适用" }
    var explanation: String { "检查对方能否移王、吃掉将军子或挡将。这是你为这次决策选择的棋理标签，不是对人的评价。" }
}
enum DecisionOrigin: String, Codable {
    case beforeMove, recollection, rulesEvidence
    var title: String { self == .beforeMove ? "落子前记录" : self == .recollection ? "事后回忆（可能不完整）" : "棋谱规则证据（非用户理由）" }
}
struct DecisionTagChange: Codable { let tag: DecisionTag; let at: Date; let author: String }
struct DecisionNote: Codable, Identifiable {
    let id: UUID
    let gameID: UUID
    let ply: Int
    let fen: String
    let gameInitialFEN: String
    let history: [String]
    let candidates: String
    let reason: String
    let origin: DecisionOrigin
    let recordedAt: Date
    let skipped: Bool
    var evidence: MateEvidence? = nil
    var tagChanges: [DecisionTagChange]
    var tag: DecisionTag { tagChanges.last?.tag ?? .unconfirmed }
}
struct ReforgePuzzle: Codable, Identifiable {
    let id: String; let version: Int; let theme: String; let fen: String
    let answers: [String]; let hint: String; let explanation: String
    let source: String; let license: String; let validation: String
}
struct ReforgeItem: Codable, Identifiable {
    let id: UUID
    let decisionID: UUID
    var dueAt: Date
    var independentPasses: Int = 0
    var waitingReason: String? = nil
    var status: String {
        if let waitingReason { return waitingReason }
        return independentPasses >= 2 ? "本主题已两次独立通过" : independentPasses == 1 ? "已一次独立通过，等待下一次新题" : "尚未独立通过"
    }
}
struct ReforgeSession: Codable, Identifiable {
    let id: UUID; let itemID: UUID; let puzzle: ReforgePuzzle
    let kind: String // new / original / practice. Never inferred from a renamed title.
    let startedAt: Date; let dueAtStart: Date; let tagAtStart: DecisionTag
    var hintAt: Date? = nil
    var submittedAt: Date? = nil
    var firstMove: String? = nil
    var outcome: String? = nil // correct / incorrect / skipped
    var countedIndependent: Bool = false
    var early: Bool { startedAt < dueAtStart }
    var finished: Bool { submittedAt != nil }
    var elapsedSeconds: Double? { submittedAt.map { max(0,$0.timeIntervalSince(startedAt)) } }
    var modeLabel: String {
        if kind == "practice" { return "针对性练习 · 不计到期独立复测" }
        if kind == "original" { return "原局面重试 · 不计新题掌握" }
        if early { return "提前练习 · 不计到期掌握" }
        return "本机未记录的新局面 · 到期复习"
    }
    var resultLabel: String {
        if outcome == "skipped" { return "已跳过 · 不计对错或掌握" }
        guard let outcome else { return "尚未提交" }
        let result = outcome == "correct" ? "答对" : "未答对"
        if hintAt != nil { return "用过提示 · \(result) · 不计独立掌握" }
        if kind == "practice" { return "针对性练习 · \(result) · 不计到期独立复测" }
        if countedIndependent { return "首次无提示答对 · 计入本主题独立通过" }
        return "无提示\(early ? "提前练习" : kind == "original" ? "原题重试" : "作答") · \(result) · 未增加掌握"
    }
}
struct ReforgeSeen: Codable { let key: String; let puzzleID: String; let version: Int; let at: Date }
struct DecisionArchive: Codable {
    var schemaVersion = 1
    var notes: [DecisionNote] = []
    var items: [ReforgeItem] = []
    var sessions: [ReforgeSession] = []
    var seen: [ReforgeSeen] = []
    var catalog: [ReforgePuzzle] = []
    var scans: [GamePatternScan]? = nil
    var clockOrigin = "device clock"
}

final class ReforgeRules {
    let engine: ChessEngine
    init() throws { engine = try ChessEngine() }
    static func key(_ fen: String) -> String { fen.split(separator:" ").prefix(4).joined(separator:" ") }
    func mateMoves(_ fen: String) throws -> [String] {
        struct Imported: Decodable { let initialFen: String }
        let _: Imported = try engine.call("importPosition",[fen,"fen"])
        let start = try engine.frames(fen:fen)[0]
        guard start.result == "*" else { return [] }
        return try start.replies.compactMap { move in
            let last = try engine.frames(fen:fen,moves:[move.code]).last!
            return last.mate && last.replies.isEmpty ? move.code : nil
        }.sorted()
    }
    func validated(_ puzzle: ReforgePuzzle) throws -> ReforgePuzzle {
        let actual = try mateMoves(puzzle.fen)
        guard puzzle.version > 0, puzzle.theme == "check-all-replies-v1", !actual.isEmpty,
              actual == puzzle.answers.sorted(), Set(puzzle.answers).count == puzzle.answers.count,
              !puzzle.source.isEmpty, !puzzle.license.isEmpty, !puzzle.validation.isEmpty else {
            throw ChessFailure.invalid("题目未通过完整答案校验，暂不提供。")
        }
        return puzzle
    }
    func knownKeys(games: [GameRecord], notes: [DecisionNote], seen: [ReforgeSeen]) throws -> Set<String> {
        var result = Set(seen.map(\.key) + notes.map { Self.key($0.fen) })
        for record in games {
            result.formUnion(try engine.frames(fen:record.initialFEN,moves:record.moves).map { Self.key($0.fen) })
        }
        for position in Lesson.all.flatMap(\.positions) {
            result.formUnion(try engine.frames(fen:position.fen,moves:position.line).map { Self.key($0.fen) })
        }
        return result
    }
}

@MainActor final class DecisionStore: ObservableObject {
    @Published private(set) var data = DecisionArchive()
    @Published private(set) var loadError: String?
    private let file: URL
    private let clock: () -> Date
    private let rules: ReforgeRules?
    private var readable = true
    private let clockOrigin: String
    var now: Date { clock() }
    var catalog: [ReforgePuzzle] { data.catalog }
    init(file: URL? = nil, clock: @escaping () -> Date = Date.init, catalog: [ReforgePuzzle]? = nil, clockOrigin: String = "device clock") {
        self.file = file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/decisions-v1.json")
        self.clock = clock; self.clockOrigin = clockOrigin
        rules = try? ReforgeRules()
        do {
            if FileManager.default.fileExists(atPath:self.file.path) {
                data = try JSONDecoder().decode(DecisionArchive.self,from:Data(contentsOf:self.file))
                guard data.schemaVersion == 1 else { throw ChessFailure.invalid("未知数据版本") }
            }
            let source: [ReforgePuzzle]
            if let catalog { source = catalog }
            else if let url = Bundle.main.url(forResource:"reforge-puzzles",withExtension:"json") {
                source = try JSONDecoder().decode([ReforgePuzzle].self,from:Data(contentsOf:url))
            } else { source = [] }
            // Invalid catalog entries are withheld. A depleted catalog becomes an explicit waiting state.
            let valid = source.compactMap { try? rules?.validated($0) }
            data.catalog = valid
            data.clockOrigin = clockOrigin
        } catch {
            data = DecisionArchive(); readable = false; loadError = "决策回炉数据无法读取，原文件已保留。\(error.localizedDescription)"
        }
    }
    func exportArchive() throws -> DecisionArchive {
        guard readable else { throw ChessFailure.invalid("决策回炉原文件无法读取，不能生成完整导出。") }
        return data
    }
    func canRecord(gameID: UUID) -> Bool { readable && data.notes.filter { $0.gameID == gameID }.count < 2 }
    func note(for item: ReforgeItem) -> DecisionNote? { data.notes.first { $0.id == item.decisionID } }
    func session(_ id: UUID) -> ReforgeSession? { data.sessions.first { $0.id == id } }
    func activeSession(itemID: UUID) -> ReforgeSession? { data.sessions.first { $0.itemID == itemID && !$0.finished } }
    @discardableResult func record(game: GameRecord, ply: Int, candidates: String, reason: String, origin: DecisionOrigin, tag: DecisionTag, skipped: Bool = false) throws -> DecisionNote {
        guard let rules, canRecord(gameID:game.id) else { throw ChessFailure.invalid("本局最多记录两处，或本地存储当前不可用。") }
        guard (0...game.moves.count).contains(ply), candidates.count <= 1000, reason.count <= 4000 else { throw ChessFailure.invalid("候选着最多 1,000 字，理由最多 4,000 字，请检查记录位置。") }
        guard origin != .beforeMove || ply == game.moves.count else { throw ChessFailure.invalid("已经走过的局面只能标记为事后回忆。") }
        guard skipped || !candidates.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ChessFailure.invalid("写下候选着或理由，也可以选择跳过。") }
        guard !data.notes.contains(where:{$0.gameID == game.id && $0.ply == ply}) else { throw ChessFailure.invalid("这个局面已经记录或跳过，不重复邀请。") }
        let history = Array(game.moves.prefix(ply)), fen = try rules.engine.frames(fen:game.initialFEN,moves:history).last!.fen
        let time = now, note = DecisionNote(id:UUID(),gameID:game.id,ply:ply,fen:fen,gameInitialFEN:game.initialFEN,history:history,candidates:skipped ? "" : candidates,reason:skipped ? "" : reason,origin:origin,recordedAt:time,skipped:skipped,tagChanges:[.init(tag:skipped ? .unconfirmed : tag,at:time,author:"user")])
        var next = data; next.notes.append(note)
        if !skipped { next.items.append(ReforgeItem(id:UUID(),decisionID:note.id,dueAt:time.addingTimeInterval(86400))) }
        try save(next); return note
    }
    func changeTag(noteID: UUID, tag: DecisionTag) throws {
        guard let index = data.notes.firstIndex(where:{$0.id == noteID}), !data.notes[index].skipped else { throw ChessFailure.invalid("这条记录无法修改标签。") }
        if data.notes[index].tag == tag { return }
        var next = data
        next.notes[index].tagChanges.append(.init(tag:tag,at:now,author:"user"))
        if let i = next.items.firstIndex(where:{$0.decisionID == noteID}) {
            guard activeSession(itemID:next.items[i].id) == nil else { throw ChessFailure.invalid("请先完成或跳过正在进行的复习，再修改标签。") }
            next.items[i].independentPasses = 0; next.items[i].waitingReason = nil; next.items[i].dueAt = now.addingTimeInterval(86400)
        }
        try save(next)
    }
    /// Persist exposure before returning any puzzle; resume the same unfinished session after a restart.
    func begin(itemID: UUID, games: [GameRecord], original: Bool = false, practice: Bool = false) throws -> ReforgeSession? {
        guard let rules, let i = data.items.firstIndex(where:{$0.id == itemID}), let note = note(for:data.items[i]) else { throw ChessFailure.invalid("复习记录不可用。") }
        if let active = activeSession(itemID:itemID) { return active }
        guard note.tag == .allReplies else { return try waiting(i,"待准备 · 请先确认适用的棋理标签") }
        let puzzle: ReforgePuzzle
        if original {
            let answers = try rules.mateMoves(note.fen)
            guard !answers.isEmpty else { return try waiting(i,"原局面不符合一步将死主题，仅供回看") }
            puzzle = ReforgePuzzle(id:"original-\(note.id)",version:1,theme:"check-all-replies-v1",fen:note.fen,answers:answers,hint:"检查每个将军后的移王、吃子和挡将。",explanation:"这次是原局面重试。答案已用棋规穷举核验；它不能证明迁移到新局面。",source:"用户本机记录 \(note.id)",license:"用户原始记录，不对外发布",validation:"chess.js 1.4.0 完整一步将死枚举")
        } else {
            let known = try rules.knownKeys(games:games,notes:data.notes,seen:data.seen)
            guard let candidate = catalog.first(where:{ !known.contains(ReforgeRules.key($0.fen)) && (try? rules.validated($0)) != nil }) else {
                return try waiting(i,"待准备 · 当前没有已验证且未见过的同类新题")
            }
            puzzle = candidate
        }
        let session = ReforgeSession(id:UUID(),itemID:itemID,puzzle:puzzle,kind:original ? "original" : practice ? "practice" : "new",startedAt:now,dueAtStart:data.items[i].dueAt,tagAtStart:note.tag)
        var next = data; next.sessions.append(session); next.items[i].waitingReason = nil
        next.seen.append(.init(key:ReforgeRules.key(puzzle.fen),puzzleID:puzzle.id,version:puzzle.version,at:session.startedAt))
        try save(next); return session
    }
    private func waiting(_ index: Int, _ reason: String) throws -> ReforgeSession? {
        var next = data; next.items[index].waitingReason = reason; try save(next); return nil
    }
    func revealHint(sessionID: UUID) throws {
        guard let i = data.sessions.firstIndex(where:{$0.id == sessionID}), !data.sessions[i].finished else { throw ChessFailure.invalid("本次作答已经结束。") }
        guard data.sessions[i].hintAt == nil else { return }
        var next = data; next.sessions[i].hintAt = now; try save(next)
    }
    func submit(sessionID: UUID, move: String?, skipped: Bool = false) throws {
        guard let rules, let i = data.sessions.firstIndex(where:{$0.id == sessionID}), !data.sessions[i].finished,
              let itemIndex = data.items.firstIndex(where:{$0.id == data.sessions[i].itemID}) else { throw ChessFailure.invalid("首次答案已经保留，不能覆盖提交。") }
        var session = data.sessions[i]
        guard now >= session.startedAt else { throw ChessFailure.invalid("设备时间早于本次开始时间，请检查后再提交。") }
        _ = try rules.validated(session.puzzle)
        if !skipped {
            guard let move, try rules.engine.frames(fen:session.puzzle.fen)[0].replies.contains(where:{$0.code == move}) else { throw ChessFailure.invalid("请先选择一个合法走法。") }
        }
        session.firstMove = skipped ? nil : move; session.submittedAt = now
        session.outcome = skipped ? "skipped" : session.puzzle.answers.contains(move ?? "") ? "correct" : "incorrect"
        session.countedIndependent = !skipped && session.outcome == "correct" && session.hintAt == nil && !session.early && session.kind == "new"
        var next = data; next.sessions[i] = session
        if session.countedIndependent { next.items[itemIndex].independentPasses += 1 }
        else if !skipped { next.items[itemIndex].independentPasses = 0 }
        let days = session.countedIndependent ? (next.items[itemIndex].independentPasses >= 2 ? 7 : 3) : 1
        next.items[itemIndex].dueAt = now.addingTimeInterval(Double(days)*86400)
        next.items[itemIndex].waitingReason = nil
        try save(next)
    }
    func saveScan(_ scan: GamePatternScan, game: GameRecord) throws {
        guard scan.gameID == game.id, scan.gameKey == MatePatternDetector.gameKey(game), ["w","b"].contains(scan.side), scan.detectorVersion == 1 else { throw ChessFailure.invalid("检查结果与棋谱不符，请重新检查。") }
        var next = data
        var scans = next.scans ?? []
        scans.removeAll { $0.gameKey == scan.gameKey || $0.gameID == scan.gameID }
        scans.append(scan); next.scans = scans
        try save(next)
    }
    func patternSummary(games: [GameRecord]) -> PatternSummary {
        let keys = Set(games.map(MatePatternDetector.gameKey))
        return PatternSummary(scans:(data.scans ?? []).filter { keys.contains($0.gameKey) })
    }
    func plan(for evidence: MateEvidence) -> ReforgeItem? {
        guard let note = data.notes.first(where:{$0.evidence?.id == evidence.id}) else { return nil }
        return data.items.first { $0.decisionID == note.id }
    }
    /// Called only after the user accepts this concrete evidence. Never fabricates a reason.
    func createEvidencePlan(_ evidence: MateEvidence, game: GameRecord) throws -> ReforgeItem {
        if let existing = plan(for:evidence) { return existing }
        guard let rules, evidence.gameID == game.id, evidence.gameKey == MatePatternDetector.gameKey(game),
              let scan = data.scans?.first(where:{$0.gameKey == evidence.gameKey}),
              scan.evidence.contains(evidence) else {
            throw ChessFailure.invalid("该局面已有记录、本局已达两处上限，或证据已过期；请检查原记录。")
        }
        guard try rules.mateMoves(evidence.fen) == evidence.answers.sorted(), !evidence.answers.isEmpty,
              !evidence.answers.contains(evidence.played) else { throw ChessFailure.invalid("证据未通过棋规复核。") }
        let date = now
        if let index = data.notes.firstIndex(where:{$0.gameID == game.id && $0.ply == evidence.ply}) {
            let previous = data.notes[index]
            guard !previous.skipped, ReforgeRules.key(previous.fen) == ReforgeRules.key(evidence.fen), previous.history == evidence.history,
                  let item = data.items.first(where:{$0.decisionID == previous.id}) else {
                throw ChessFailure.invalid("原记录已跳过或与证据不一致；请保留并检查原记录。")
            }
            var next = data
            next.notes[index].evidence = evidence
            if previous.tag != .allReplies { next.notes[index].tagChanges.append(.init(tag:.allReplies,at:date,author:"user-confirmed-rule-evidence")) }
            try save(next); return item
        }
        guard canRecord(gameID:game.id) else { throw ChessFailure.invalid("本局已达两处记录上限。") }
        let note = DecisionNote(id:UUID(),gameID:game.id,ply:evidence.ply,fen:evidence.fen,gameInitialFEN:game.initialFEN,history:evidence.history,candidates:"",reason:"",origin:.rulesEvidence,recordedAt:date,skipped:false,evidence:evidence,tagChanges:[.init(tag:.allReplies,at:date,author:"user-confirmed-rule-evidence")])
        let item = ReforgeItem(id:UUID(),decisionID:note.id,dueAt:date.addingTimeInterval(86400))
        var next = data; next.notes.append(note); next.items.append(item)
        try save(next); return item
    }
    private func save(_ next: DecisionArchive) throws {
        guard readable else { throw ChessFailure.invalid("原文件无法读取，未写入新数据。") }
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(next).write(to:file,options:.atomic)
            data = next
        } catch { throw ChessFailure.invalid("本次未能保存，请检查设备空间后重试；没有确认提交。") }
    }
}
