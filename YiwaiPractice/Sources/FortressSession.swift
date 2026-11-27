import Foundation

protocol FortressFrame {
    var fen: String { get }
    var turn: String { get }
    var result: String { get }
    var fortressLegalMoves: [String] { get }
}

enum FortressSessionError: LocalizedError {
    case invalidSeed, illegalMove, invalidReply, terminal, unexpectedResult, moveLimit
    var errorDescription: String? {
        switch self {
        case .invalidSeed: return "挑战局面无效，无法开始。"
        case .illegalMove: return "请选择棋规允许的白方走法。"
        case .invalidReply: return "防守规则与棋规不一致；已保留上一步，停止本次操作。"
        case .terminal: return "本局已结束，请重新开始。"
        case .unexpectedResult: return "出现意外胜负；这不是已验证的结论，操作未保存。"
        case .moveLimit: return "已达到本次练习步数上限，未宣称棋局和棋。"
        }
    }
}

/// A complete attack/reply pair is committed atomically only after legality and outcome checks.
struct FortressSession<F: FortressFrame> {
    typealias Replay = (String, [String]) throws -> F
    struct Turn { let moves: [String]; let frame: F; let reply: String? }
    static var moveLimit: Int { 200 }
    let seed: Int
    var initialFEN: String { FortressPolicy.seeds[seed] }
    private(set) var history: [Turn]
    var current: Turn { history[history.count - 1] }
    var canMove: Bool { current.frame.result == "*" && current.frame.turn == "w" && current.moves.count < Self.moveLimit }
    var limitReached: Bool { current.frame.result == "*" && current.moves.count >= Self.moveLimit }
    init(seed: Int, replay: Replay) throws {
        guard FortressPolicy.seeds.indices.contains(seed) else { throw FortressSessionError.invalidSeed }
        let frame = try replay(FortressPolicy.seeds[seed], [])
        guard frame.turn == "w", frame.result == "*", !frame.fortressLegalMoves.isEmpty else { throw FortressSessionError.invalidSeed }
        self.seed = seed
        history = [.init(moves: [], frame: frame, reply: nil)]
    }
    mutating func play(_ move: String, replay: Replay) throws {
        guard current.frame.result == "*" else { throw FortressSessionError.terminal }
        guard current.moves.count < Self.moveLimit else { throw FortressSessionError.moveLimit }
        guard current.frame.turn == "w", current.frame.fortressLegalMoves.contains(move) else { throw FortressSessionError.illegalMove }
        var moves = current.moves + [move]
        var frame = try replay(initialFEN, moves)
        guard frame.turn == "b" else { throw FortressSessionError.invalidReply }
        var reply: String?
        if frame.result == "*" {
            guard case .move(let code) = FortressPolicy.reply(fen: frame.fen, legalMoves: frame.fortressLegalMoves),
                  frame.fortressLegalMoves.contains(code) else { throw FortressSessionError.invalidReply }
            moves.append(code)
            frame = try replay(initialFEN, moves)
            guard frame.turn == "w" else { throw FortressSessionError.invalidReply }
            reply = code
        }
        guard frame.result == "*" || frame.result == "1/2-1/2" else { throw FortressSessionError.unexpectedResult }
        guard frame.result != "*" || (frame.turn == "w" && !frame.fortressLegalMoves.isEmpty) else { throw FortressSessionError.invalidReply }
        history.append(.init(moves: moves, frame: frame, reply: reply))
    }
    mutating func undo() { if history.count > 1 { history.removeLast() } }
    mutating func restart() { history = [history[0]] }
}

/// Predict first; answer is determined by the same legal rules engine, not a heuristic.
struct FortressQuestion {
    let fen: String
    let title: String
    let explanation: String
    let expected: Bool
    static let examples = [
        FortressQuestion(fen: "8/k7/8/8/8/8/P6B/K7 b - - 0 1", title: "错色象：能返回角落吗？", explanation: "h2 的象只能沿深色格移动，不能攻击浅色格 a8。黑王可回到角落。", expected: true),
        FortressQuestion(fen: "8/k7/8/8/8/8/P7/K6B b - - 0 1", title: "只移动一个象：条件仍成立吗？", explanation: "h1 的象控制 a8，黑王不能回去。这是防守规则的反例，不等于证明白方必胜。", expected: false),
        FortressQuestion(fen: "8/k7/8/8/8/8/P7/K2B4 b - - 0 1", title: "新局面：角落还安全吗？", explanation: "d1 的象与 h1 同为浅色象，但当前不攻击 a8。回角这一步合法，不代表整个错色象定理适用。", expected: true)
    ]
    func answer<F: FortressFrame>(using frame: F) -> Bool? {
        guard frame.turn == "b", frame.result == "*", !frame.fortressLegalMoves.isEmpty else { return nil }
        return frame.fortressLegalMoves.contains("a7a8")
    }
}
