import Foundation

/// Proof-driven corner shelter; only the canonical White a-file case.
/// The app's existing legal-move engine is authoritative for legality and terminal status.
/// Never call for live online play; this is an offline learning feature.
enum FortressPolicy {
    enum Reply: Equatable {
        case move(String), terminalOrNoLegalMove, unsupported, inconsistent
    }
    static let seeds = [
        "8/Pk6/4K3/8/3B4/8/8/8 w - - 0 1",
        "k7/8/8/8/4K3/8/P7/2B5 w - - 0 1",
        "8/1k6/4K3/P7/8/6B1/8/8 w - - 0 1"
    ]
    private static let corner = 56
    private static let zone: Set<Int> = [48,49,56,57]
    private static func name(_ square: Int) -> String {
        String(Array("abcdefgh")[square % 8]) + String(square / 8 + 1)
    }
    private static func adjacent(_ a: Int, _ b: Int) -> Bool {
        max(abs(a % 8 - b % 8), abs(a / 8 - b / 8)) == 1
    }
    private static func dark(_ s: Int) -> Bool { (s % 8 + s / 8) % 2 == 0 }
    private static func parse(_ fen: String) -> [Int: Character]? {
        let fields = fen.split(separator: " ")
        guard fields.count == 6, fields[1] == "b", fields[2] == "-", fields[3] == "-",
              let half = Int(fields[4]), half >= 0, let full = Int(fields[5]), full >= 1 else { return nil }
        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        var board = [Int: Character]()
        for (r, row) in ranks.enumerated() {
            var file = 0
            for c in row {
                if let n = c.wholeNumberValue, (1...8).contains(n), c.isASCII { file += n }
                else if "KkPBRQN".contains(c), file < 8 {
                    board[(7-r)*8 + file] = c; file += 1
                } else { return nil }
                if file > 8 { return nil }
            }
            if file != 8 { return nil }
        }
        return board
    }
    /// Pass the actual legal UCI replies after the attacker's move, not pseudo-legal moves.
    /// Promotion is accepted only in the immediate-successor pattern; caller owns history.
    static func reply(fen: String, legalMoves: [String]) -> Reply {
        guard let board = parse(fen) else { return .unsupported }
        let whiteKings = board.filter { $0.value == "K" }.map(\.key)
        let blackKings = board.filter { $0.value == "k" }.map(\.key)
        guard whiteKings.count == 1, blackKings.count == 1,
              let w = whiteKings.first, let k = blackKings.first, zone.contains(k), !adjacent(w,k) else { return .unsupported }
        let extra = board.filter { $0.value != "K" && $0.value != "k" }
        let pawns = extra.filter { $0.value == "P" }.map(\.key)
        let regular = pawns.count == 1 && pawns[0] % 8 == 0 && (8...48).contains(pawns[0]) &&
            extra.count <= 2 && extra.allSatisfy { $0.value == "P" || ($0.value == "B" && dark($0.key)) }
        let promotion = pawns.isEmpty && extra.count <= 2 && extra[corner].map { "QRBN".contains($0) } == true &&
            extra.allSatisfy { $0.key == corner || ($0.value == "B" && dark($0.key)) }
        guard regular || promotion else { return .unsupported }
        let prefix = name(k)
        if k != corner {
            let target = prefix + "a8"
            return legalMoves.contains(target) ? .move(target) : .inconsistent
        }
        if legalMoves.isEmpty { return .terminalOrNoLegalMove }
        let permitted = Set(zone.filter { $0 != k }.map { prefix + name($0) })
        guard legalMoves.allSatisfy({ permitted.contains($0) }), let move = legalMoves.sorted().first else { return .inconsistent }
        return .move(move)
    }
}
