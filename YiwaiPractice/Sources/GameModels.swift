import Foundation
import Combine

final class SearchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
enum EngineWorker { static let queue = DispatchQueue(label:"yiwai.engine",qos:.utility) }

struct PositionScore: Codable, Equatable {
    let kind: String
    var cp: Int? = nil
    var winner: String? = nil
    var mateIn: Int? = nil
    static func fromSideToMove(_ cp: Int, turn: String) -> Self { .init(kind:"cp",cp:turn == "w" ? cp : -cp) }
    static func loss(before: Self, after: Self, mover: String) -> Int? {
        guard before.kind == "cp", after.kind == "cp", let a = before.cp, let b = after.cp else { return nil }
        return max(0,(a-b)*(mover == "w" ? 1 : -1))
    }
    var label: String {
        if kind == "mate" { return "\(winner == "w" ? "白" : "黑")方将死线 · \(mateIn ?? 0) 步" }
        guard let cp, kind == "cp" else { return "未完成估值" }
        return String(format:"白方 %+.2f",Double(cp)/100)
    }
}
struct EngineLine: Codable { let score: PositionScore; let pv: [String]; let san: [String]; let depth: Int; let nodes: Int; let limited: Bool }
struct MoveSearch: Decodable { let searchID: String; let fen: String; let history: [String]; let move: String; let line: EngineLine }
struct MoveReview: Codable {
    let searchID: String; let fen: String; let history: [String]
    let best: EngineLine; let played: EngineLine
    let moveSAN: String; let captured: String; let promotion: String; let check: Bool; let mate: Bool
    var mover: String { fen.split(separator:" ").dropFirst().first.map(String.init) ?? "w" }
    var loss: Int? { PositionScore.loss(before:best.score,after:played.score,mover:mover) }
    var title: String {
        if mate { return "完成将死" }
        if best.score.kind == "mate" || played.score.kind == "mate" { return "查看将死变化" }
        guard let loss else { return "未完成分析" }
        return loss >= 150 ? "值得重点复看" : loss >= 50 ? "比较另一条路线" : "本次搜索差异较小"
    }
    var explanation: String {
        let side = mover == "w" ? "白方" : "黑方"
        var text = "\(side)走了 \(moveSAN)。"
        if mate { text += "棋规确认对方没有合法应将，棋局结束。" }
        else if check { text += "这一步形成将军，变化线从对方合法应将继续。" }
        if !captured.isEmpty { text += "这一步吃掉了\(["p":"兵","n":"马","b":"象","r":"车","q":"后"][captured] ?? captured)。" }
        if !promotion.isEmpty { text += "兵升变为\(["q":"后","r":"车","b":"象","n":"马"][promotion] ?? promotion)。" }
        if let loss { text += String(format:"同一方视角比较，选择这步后的估值比本次首选低 %.2f 分。",Double(loss)/100) }
        else { text += "涉及将死，单独展示，不换算为分值或计入平均。" }
        text += "点开两条变化线，比较对手如何回应。浅层搜索可能遗漏更深战术。"
        return text
    }
}
struct GameSnapshot: Decodable { let frame: ChessFrame; let sans: [String]; let pgn: String; let result: String; let reason: String }
struct GameRecord: Codable, Identifiable {
    var id = UUID(); var created = Date(); var updated = Date()
    var initialFEN = ChessEngine.initialFEN
    var moves: [String] = []; var human = "w"; var level = 1; var ending: String? = nil
    var analyses: [String:MoveReview] = [:]
    var reviewReport: GameReviewReport? = nil
    var source: String? = nil
    var importedHeaders: [String:String]? = nil
    // Optional additions keep pre-capsule games readable without a migration.
    var originalPGN: String? = nil
    var personalNote: String? = nil
    var title: String { if let source { return source.uppercased() + (moves.isEmpty ? " · 独立局面" : " · \(moves.count) 半回合") }; return "执\(human == "w" ? "白" : "黑") · \(moves.count) 半回合" }
    var info: [String:String] {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy.MM.dd"
        var values = ["human":human,"ending":ending ?? "","date":formatter.string(from:created)]
        if let importedHeaders, let data = try? JSONEncoder().encode(importedHeaders) { values["importHeaders"] = String(data:data,encoding:.utf8) }
        return values
    }
}
extension ChessEngine {
    func game(_ record: GameRecord, through ply: Int? = nil) throws -> GameSnapshot {
        try call("game",[record.initialFEN,Array(record.moves.prefix(ply ?? record.moves.count)),ply == nil ? record.info : ["human":record.human]])
    }
}

@MainActor final class GameController: ObservableObject {
    @Published private(set) var records: [GameRecord] = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var snapshot: GameSnapshot?
    @Published private(set) var thinking = false
    @Published private(set) var paused = true
    @Published var selected: String?
    @Published var promotions: [ChessMove] = []
    @Published var errorMessage: String?
    private let file: URL
    private var readFailed = false
    private var rules: ChessEngine?
    private var token: SearchCancellation?
    private var requestID = UUID()
    var current: GameRecord? { records.first { $0.id == currentID } }
    var canUndo: Bool { guard let current else { return false }; return current.moves.count >= (current.human == "w" ? 1 : 2) }
    var canMove: Bool { !paused && !thinking && current?.ending == nil && snapshot?.result == "*" && snapshot?.frame.turn == current?.human }
    var targets: Set<String> { Set(snapshot?.frame.replies.filter { $0.from == selected }.map(\.to) ?? []) }
    var status: String {
        guard let snapshot, let current else { return "开始一局离线对弈" }
        if snapshot.result != "*" { return "\(snapshot.result) · \(snapshot.reason)" }
        if current.ending == "saved" { return "已保存，可在棋谱里复盘或继续" }
        if paused { return "已暂停 · 点继续对弈" }
        if thinking { return "Seed 正在思考…" }
        return snapshot.frame.check ? "你的王被将军，请应将" : "轮到你 · 先点棋子，再点目标格"
    }
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/games-v1.json")
        do {
            rules = try ChessEngine()
            if FileManager.default.fileExists(atPath:self.file.path) {
                records = try JSONDecoder().decode([GameRecord].self,from:Data(contentsOf:self.file))
                // Validate persisted move histories before displaying or overwriting them.
                for record in records { _ = try rules?.game(record) }
                currentID = records.first(where:{$0.source == nil})?.id; refresh()
            }
        } catch { readFailed = true; errorMessage = "棋谱读取失败，原文件已保留：\(error.localizedDescription)" }
    }
    func newGame(human: String, level: Int, fen: String = ChessEngine.initialFEN) {
        guard !readFailed else { return }
        pause()
        let game = GameRecord(initialFEN:fen,human:human,level:level)
        do { _ = try rules?.game(game) } catch { errorMessage = error.localizedDescription; return }
        records.insert(game,at:0); currentID = game.id; paused = false; selected = nil; promotions = []; refresh(); persist(); startComputer()
    }
    @discardableResult func importPosition(_ text: String, format: String) throws -> GameRecord {
        guard !readFailed, let rules else { throw ChessFailure.invalid("棋谱存储不可用，原文件已保留。") }
        guard text.utf8.count <= (format == "pgn" ? 200000 : 512) else { throw ChessFailure.invalid("文件过大：FEN 最多 512 字节，PGN 最多 200 KB。") }
        struct Imported: Decodable { let initialFen: String; let moves: [String]; let headers: [String:String] }
        let input: Imported = try rules.call("importPosition",[text,format])
        let record = GameRecord(initialFEN:input.initialFen,moves:input.moves,source:format,importedHeaders:input.headers,originalPGN:format == "pgn" ? text : nil)
        _ = try rules.game(record)
        let next = [record] + records
        try writeRecords(next)
        pause(); records = next
        return record
    }
    func savePersonalNote(_ id: UUID, text: String) throws {
        guard text.count <= 10000 else { throw ChessFailure.invalid("备注最多 10,000 字；请缩短后保存。") }
        guard let i = records.firstIndex(where:{$0.id == id}) else { throw ChessFailure.invalid("这盘棋已不在本机记录中。") }
        var next = records
        next[i].personalNote = text; next[i].updated = Date()
        try writeRecords(next)
        records = next
    }
    func capsuleRecords() throws -> [GameRecord] {
        guard !readFailed else { throw ChessFailure.invalid("棋谱原文件无法读取，不能生成完整导出。原文件已保留。") }
        return records
    }
    func resume(_ id: UUID? = nil) {
        pause()
        if let id { guard records.first(where:{$0.id == id})?.source == nil else { return }; currentID = id }
        guard let i = records.firstIndex(where:{$0.id == currentID}) else { return }
        if records[i].ending == "saved" { records[i].ending = nil }
        paused = false; refresh(); persist(); startComputer()
    }
    func pause() { token?.cancel(); token = nil; requestID = UUID(); thinking = false; paused = true; selected = nil; promotions = [] }
    func tap(_ square: String) {
        guard canMove else { return }
        if let selected {
            let candidates = snapshot?.frame.replies.filter { $0.from == selected && $0.to == square } ?? []
            if candidates.count > 1 { promotions = candidates; return }
            if let move = candidates.first { play(move.code); return }
        }
        selected = snapshot?.frame.pieces.contains(where:{$0.square == square && $0.color == current?.human}) == true ? square : nil
    }
    func play(_ code: String) {
        guard canMove, snapshot?.frame.replies.contains(where:{$0.code == code}) == true else { return }
        append(code); startComputer()
    }
    private func append(_ code: String) {
        guard let i = records.firstIndex(where:{$0.id == currentID}) else { return }
        guard records[i].moves.count < 600 else { pause(); errorMessage = "本局已达600半回合，请保存复盘。"; return }
        var next = records[i]; next.moves.append(code); next.updated = Date(); next.analyses = [:]; next.reviewReport = nil
        do { let state = try rules?.game(next); records[i] = next; snapshot = state; selected = nil; promotions = []; persist() }
        catch { pause(); errorMessage = "走子未提交：\(error.localizedDescription)" }
    }
    func undo() {
        guard canUndo else { return }
        let wasPaused = paused; pause()
        guard let i = records.firstIndex(where:{$0.id == currentID}), !records[i].moves.isEmpty else { return }
        records[i].ending = nil; records[i].moves.removeLast()
        // Return to the human's turn, removing the AI reply and human move together.
        if let state = try? rules?.game(records[i]), state.frame.turn != records[i].human, !records[i].moves.isEmpty { records[i].moves.removeLast() }
        records[i].analyses = [:]; records[i].reviewReport = nil; records[i].updated = Date(); paused = wasPaused; refresh(); persist()
    }
    func finish(resign: Bool) {
        pause(); guard let i = records.firstIndex(where:{$0.id == currentID}) else { return }
        if snapshot?.result == "*" { records[i].ending = resign ? "resigned" : "saved"; records[i].reviewReport = nil }
        records[i].updated = Date(); refresh(); persist()
    }
    func saveAnalysis(_ value: MoveReview, ply: Int, record: GameRecord) {
        guard let i = records.firstIndex(where:{$0.id == record.id}), records[i].moves == record.moves,
              value.history == Array(record.moves.prefix(ply)) else { return }
        records[i].analyses[String(ply)] = value; persist()
    }
    func saveReview(_ value: GameReviewReport, record: GameRecord) {
        guard let i = records.firstIndex(where:{$0.id == record.id}), value.matches(records[i]),
              records[i].ending == record.ending else { return }
        records[i].reviewReport = value; persist()
    }
    private func refresh() {
        guard let current else { snapshot = nil; return }
        do { snapshot = try rules?.game(current) } catch { errorMessage = error.localizedDescription }
    }
    private func persist() {
        guard !readFailed else { return }
        do { try writeRecords(records) }
        catch { errorMessage = "棋谱未能保存，请检查设备空间。当前棋局仍在内存中。" }
    }
    private func writeRecords(_ value: [GameRecord]) throws {
        guard !readFailed else { throw ChessFailure.invalid("棋谱存储不可用，原文件已保留。") }
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(value).write(to:file,options:.atomic)
        } catch { throw ChessFailure.invalid("未能保存到设备，请检查可用空间后重试。") }
    }
    private func startComputer() {
        guard !paused, let record = current, record.ending == nil, let snapshot, snapshot.result == "*", snapshot.frame.turn != record.human else { return }
        token?.cancel(); let cancellation = SearchCancellation(); token = cancellation
        let id = UUID(); requestID = id; thinking = true
        let fen = snapshot.frame.fen
        let depth = [2,4,5][min(2,max(0,record.level))], time = [300,1000,1800][min(2,max(0,record.level))]
        EngineWorker.queue.async { [weak self] in
            let result: Result<MoveSearch,Error> = Result {
                let engine = try ChessEngine(cancellation:cancellation)
                return try engine.call("search",[["fen":record.initialFEN,"moves":record.moves], ["maxDepth":depth,"timeMs":time,"maxNodes":60000],id.uuidString])
            }
            Task { @MainActor [weak self] in
                guard let self, !cancellation.isCancelled, self.requestID == id, self.currentID == record.id,
                      self.current?.moves == record.moves, self.snapshot?.frame.fen == fen, !self.paused else { return }
                self.thinking = false
                switch result {
                case .success(let answer):
                    guard answer.searchID == id.uuidString, answer.history == record.moves, answer.fen == fen,
                          self.snapshot?.frame.replies.contains(where:{$0.code == answer.move}) == true else { self.pause(); self.errorMessage = "引擎结果与当前棋局不符，已暂停。"; return }
                    self.append(answer.move)
                case .failure(let error): self.pause(); self.errorMessage = "电脑暂时无法走子：\(error.localizedDescription)"
                }
            }
        }
    }
}
