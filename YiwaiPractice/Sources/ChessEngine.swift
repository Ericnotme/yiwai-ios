import Foundation
import JavaScriptCore

struct ChessPiece: Codable, Identifiable {
    let square: String
    let type: String
    let color: String
    var id: String { square }
    var symbol: String { (["k":"♚", "q":"♛", "r":"♜", "b":"♝", "n":"♞", "p":"♟"][type] ?? "") + "\u{FE0E}" }
    var name: String { (color == "w" ? "白" : "黑") + (["k":"王", "q":"后", "r":"车", "b":"象", "n":"马", "p":"兵"][type] ?? "") }
}
struct ChessMove: Codable { let from: String; let to: String; let san: String; let promotion: String
    var code: String { from + to + promotion }
}
struct ChessFrame: Codable {
    let fen: String; let san: String; let from: String; let to: String
    let turn: String; let check: Bool; let mate: Bool
    let pieces: [ChessPiece]; let replies: [ChessMove]
    let result: String; let reason: String
}
enum ChessFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}
private struct BridgeFailure: Decodable { let error: String }
final class ChessEngine {
    private let context: JSContext
    static let initialFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    init(bundle: Bundle = .main, cancellation: SearchCancellation? = nil) throws {
        guard let context = JSContext() else { throw ChessFailure.invalid("棋规未能启动") }
        self.context = context
        if let cancellation {
            let callback: @convention(block) () -> Bool = { cancellation.isCancelled }
            context.setObject(callback,forKeyedSubscript:"nativeCancelled" as NSString)
        }
        for name in ["chess", "seed-engine", "position-import", "chess-bridge"] {
            guard let url = bundle.url(forResource:name, withExtension:"js") else { throw ChessFailure.invalid("缺少本地棋规文件") }
            context.evaluateScript(try String(contentsOf:url, encoding:.utf8))
            if let error = context.exception { throw ChessFailure.invalid(error.toString()) }
        }
    }
    func call<T: Decodable>(_ method: String, _ arguments: [Any], as type: T.Type = T.self) throws -> T {
        context.exception = nil
        guard let json = context.objectForKeyedSubscript("YiwaiChess")?.invokeMethod(method,withArguments:arguments)?.toString(), let data = json.data(using:.utf8) else { throw ChessFailure.invalid("本地棋引擎没有返回结果") }
        if let error = context.exception { throw ChessFailure.invalid(error.toString()) }
        if let failure = try? JSONDecoder().decode(BridgeFailure.self,from:data) { throw ChessFailure.invalid(failure.error) }
        return try JSONDecoder().decode(T.self,from:data)
    }
    func frames(fen: String, moves: [String] = []) throws -> [ChessFrame] {
        guard let result = context.objectForKeyedSubscript("YiwaiChess")?.invokeMethod("inspect", withArguments:[fen,moves])?.toString(), let data = result.data(using:.utf8) else { throw ChessFailure.invalid("棋规返回为空") }
        struct Response: Decodable { let frames: [ChessFrame]?; let error: String? }
        let response = try JSONDecoder().decode(Response.self, from:data)
        guard let frames = response.frames else { throw ChessFailure.invalid(response.error ?? "局面无效") }
        return frames
    }
    func validateReview(_ report: GameReviewReport, record: GameRecord) throws {
        struct Validation: Decodable { let valid: Bool }
        let entries: [[String:Any]] = report.entries.map { ["ply":$0.ply,"bestPV":$0.bestPV,"playedPV":$0.playedPV] }
        let result: Validation = try call("validateReview",[record.initialFEN,record.moves,entries])
        guard result.valid else { throw ChessFailure.invalid("缓存报告未通过棋规校验") }
    }
    func perft(fen: String, depth: Int) -> Int {
        Int(context.objectForKeyedSubscript("YiwaiChess")?.invokeMethod("perft",withArguments:[fen,depth])?.toInt32() ?? 0)
    }
}
