import Foundation
import Combine
import CryptoKit

struct MateEvidence: Codable, Identifiable, Equatable {
    var id: String { "\(gameKey):\(ply)" }
    let gameID: UUID
    let gameKey: String
    let side: String
    let ply: Int
    let fen: String
    let initialFEN: String
    let history: [String]
    let played: String
    let playedSAN: String
    let answers: [String]
    let replyCount: Int
    let replyExamples: [String]
    let detectorVersion: Int
    var moveNumber: Int { Int(fen.split(separator:" ").last ?? "1") ?? 1 }
    var explanation: String {
        "这盘你确认执\(side == "w" ? "白" : "黑")。第 \(moveNumber) 回合走了 \(playedSAN)，当时也有 \(answers.joined(separator:"、")) 可一步将死：将军且对方没有合法应将。实际走法后仍有 \(replyCount) 个合法应对。它可能仍然获胜；这里只证明没有走当步的将死着，不判断你当时的理由。"
    }
}
struct GamePatternScan: Codable, Identifiable {
    var id: String { gameKey }
    let gameID: UUID
    let gameKey: String
    let side: String
    let scannedAt: Date
    let examined: Int
    let opportunities: Int
    let misses: Int
    let evidence: [MateEvidence]
    let detectorVersion: Int
}
struct PatternSummary {
    let scans: [GamePatternScan]
    var gamesWithEvidence: Int { scans.filter { !$0.evidence.isEmpty }.count }
    var distinctPositions: Int { Set(scans.flatMap(\.evidence).map { ReforgeRules.key($0.fen) }).count }
    var repeated: Bool { gamesWithEvidence >= 2 && distinctPositions >= 2 }
    var label: String {
        if repeated { return "重复证据：\(gamesWithEvidence) 盘棋、\(distinctPositions) 个不同局面漏走当步将死" }
        if gamesWithEvidence > 0 { return "发现局面证据，但不足以判断重复模式" }
        return scans.isEmpty ? "尚未检查棋谱" : "本次未发现漏走一步将死；不代表没有其他问题"
    }
}
final class MatePatternDetector {
    private let engine: ChessEngine
    init(cancellation: SearchCancellation? = nil) throws { engine = try ChessEngine(cancellation:cancellation) }
    static func gameKey(_ game: GameRecord) -> String {
        let value = ReforgeRules.key(game.initialFEN)+"|"+game.moves.joined(separator:",")
        return SHA256.hash(data:Data(value.utf8)).map { String(format:"%02x",$0) }.joined()
    }
    func scan(_ game: GameRecord, side: String, at date: Date) throws -> GamePatternScan {
        struct Found: Decodable { let ply: Int; let fen: String; let played: String; let playedSAN: String; let answers: [String]; let replyCount: Int; let replyExamples: [String] }
        struct Result: Decodable { let examined: Int; let opportunities: Int; let misses: Int; let evidence: [Found] }
        let result: Result = try engine.call("scanMissedMate",[game.initialFEN,game.moves,side])
        let key = Self.gameKey(game)
        let evidence = result.evidence.map { e in
            MateEvidence(gameID:game.id,gameKey:key,side:side,ply:e.ply,fen:e.fen,initialFEN:game.initialFEN,history:Array(game.moves.prefix(e.ply)),played:e.played,playedSAN:e.playedSAN,answers:e.answers,replyCount:e.replyCount,replyExamples:e.replyExamples,detectorVersion:1)
        }
        return GamePatternScan(gameID:game.id,gameKey:key,side:side,scannedAt:date,examined:result.examined,opportunities:result.opportunities,misses:result.misses,evidence:evidence,detectorVersion:1)
    }
}
@MainActor final class PatternScanController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var result: GamePatternScan?
    @Published private(set) var completionID = UUID()
    @Published private(set) var error: String?
    private var token: SearchCancellation?
    private var requestID = UUID()
    private static let queue = DispatchQueue(label:"yiwai.pattern-scan",qos:.userInitiated)
    func scan(_ game: GameRecord, side: String, at date: Date) {
        cancel(); result = nil; error = nil; busy = true
        let cancellation = SearchCancellation(), id = UUID(); token = cancellation; requestID = id
        Self.queue.async {
            let value = Result { try MatePatternDetector(cancellation:cancellation).scan(game,side:side,at:date) }
            Task { @MainActor [weak self] in
                guard let self, self.requestID == id, !cancellation.isCancelled else { return }
                self.busy = false
                switch value { case .success(let scan): self.result = scan; self.completionID = UUID(); case .failure(let failure): self.error = failure.localizedDescription }
            }
        }
    }
    func cancel() { token?.cancel(); token = nil; requestID = UUID(); busy = false }
}
