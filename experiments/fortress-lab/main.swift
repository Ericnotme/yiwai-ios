import Foundation
var total = 0, promotions = 0, noLegal = 0
while let line = readLine() {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    precondition(fields.count == 4)
    let moves = fields[1].split(separator: ",").map(String.init)
    let actual = FortressPolicy.reply(fen: fields[0], legalMoves: moves)
    let expected: FortressPolicy.Reply = fields[2] == "terminal" ? .terminalOrNoLegalMove : .move(fields[2])
    precondition(actual == expected, "Mismatch: \(line), \(actual)")
    total += 1
    if fields[3] == "promotion" { promotions += 1 }
    if fields[2] == "terminal" { noLegal += 1 }
}
precondition(total == 48243 && promotions == 6928 && noLegal == 217)
precondition(FortressPolicy.reply(fen:"8/k7/8/8/8/8/P7/K6B b - - 0 1",legalMoves:["a7b6"]) == .unsupported)
precondition(FortressPolicy.reply(fen:"8/Pk6/4K3/8/3B4/8/8/8 b - - 0 1",legalMoves:[]) == .inconsistent)
precondition(FortressPolicy.reply(fen:"8/P7/4K3/8/3B4/8/7k/8 b - - 0 1",legalMoves:["h2h1"]) == .unsupported)
precondition(FortressPolicy.reply(fen:"k7/8/8/8/4K3/8/P7/2B5 b - - 0 1",legalMoves:["a8c8"]) == .inconsistent)
precondition(FortressPolicy.reply(fen:"k7/8/8/8/4K3/8/P7/2B5 w - - 0 1",legalMoves:[]) == .unsupported)
print("PASS: \(total) reply fixtures, \(promotions) promotions, \(noLegal) no-legal-move cases, 5 negative guards")
