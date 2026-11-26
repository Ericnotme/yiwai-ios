import Foundation
import CryptoKit

struct ConditionFamily: Codable, Identifiable { let id:String; let title:String; let relation:String }
struct ConditionPosition: Codable, Identifiable {
    let id:String; let version:Int; let pgn:String; let fen:String; let proofMoves:[String]; let answers:[String]
    let family:String; let condition:String; let captureOpportunity:Bool; let defenseChanged:Bool
    let critical:String?; let distractingCapture:String?; let relation:String
    var digest:String {
        let parts=[id,String(version),ReforgeRules.key(fen),pgn,proofMoves.joined(separator:","),answers.sorted().joined(separator:","),family,condition,captureOpportunity ? "1":"0",defenseChanged ? "1":"0",critical ?? "",distractingCapture ?? ""]
        return SHA256.hash(data:Data(parts.joined(separator:"|").utf8)).map { String(format:"%02x",$0) }.joined()
    }
}
struct ConditionEngineCheck: Codable {
    let id:String; let digest:String; let engine:String; let checkedAt:String
    let best:String?; let mate:Int?; let winner:String?; let depth:Int; let pv:[String]
}
struct ConditionCatalog: Codable {
    let schemaVersion:Int; let experimental:Bool; let source:String; let license:String
    let families:[ConditionFamily]; let positions:[ConditionPosition]
    static func bundled() throws -> Self {
        guard let url=Bundle.main.url(forResource:"condition-catalog",withExtension:"json") else { throw ChessFailure.invalid("对照题库尚未准备好。") }
        return try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }
    static func engineChecks() throws -> [ConditionEngineCheck] {
        guard let url=Bundle.main.url(forResource:"condition-engine-verification",withExtension:"json") else { throw ChessFailure.invalid("缺少引擎复核证据。") }
        return try JSONDecoder().decode([ConditionEngineCheck].self,from:Data(contentsOf:url))
    }
}
final class ConditionRules {
    let rules:ReforgeRules
    init() throws { rules=try ReforgeRules() }
    func validate(_ position:ConditionPosition, check:ConditionEngineCheck? = nil, requireEngine:Bool = true) throws {
        struct Imported:Decodable { let initialFen:String; let moves:[String] }
        let proof:Imported=try rules.engine.call("importPosition",[position.pgn,"pgn"])
        guard proof.initialFen == GameRecord().initialFEN, proof.moves == position.proofMoves, !proof.moves.isEmpty,
              let last=try rules.engine.frames(fen:proof.initialFen,moves:proof.moves).last,
              ReforgeRules.key(last.fen)==ReforgeRules.key(position.fen), last.result == "*", position.version > 0,
              try rules.mateMoves(position.fen)==position.answers.sorted(), Set(position.answers).count==position.answers.count else {
            throw ChessFailure.invalid("题目缺少有效标准开局证明，或完整答案不符。")
        }
        if position.family != "transfer" {
            guard ["A","B","C","D"].contains(position.condition), let critical=position.critical,
                  last.replies.contains(where:{$0.code==critical}), let capture=position.distractingCapture,
                  position.captureOpportunity == ["B","D"].contains(position.condition),
                  position.defenseChanged == ["C","D"].contains(position.condition),
                  position.answers == (position.defenseChanged ? [] : [critical]),
                  (last.replies.first(where:{$0.code==capture})?.san.contains("x") ?? false)==position.captureOpportunity,
                  !position.answers.contains(capture) else { throw ChessFailure.invalid("四条件约束不完整，整组暂不提供。") }
        }
        if requireEngine {
            guard let check, check.id==position.id, check.digest==position.digest,
                  check.engine==GameReviewReport.engineName, check.depth > 0, !check.checkedAt.isEmpty,
                  let best=check.best, last.replies.contains(where:{$0.code==best}) else { throw ChessFailure.invalid("引擎复核缺失或已过期。") }
            let engineMate=check.mate==1 && check.winner==last.turn
            guard engineMate == !position.answers.isEmpty,
                  !engineMate || position.answers.contains(best) else { throw ChessFailure.invalid("引擎与完整棋规答案不一致。") }
            _=try rules.engine.frames(fen:position.fen,moves:check.pv)
        }
    }
    func available(_ catalog:ConditionCatalog, checks:[ConditionEngineCheck]) -> (positions:[ConditionPosition], issues:[String]) {
        var valid:[ConditionPosition]=[], issues:[String]=[]
        guard catalog.schemaVersion==1, !catalog.source.isEmpty, !catalog.license.isEmpty else { return ([],["题库来源或版本不可用"]) }
        for family in catalog.families {
            let group=catalog.positions.filter{$0.family==family.id}
            do {
                guard group.count==4, Set(group.map(\.condition))==Set(["A","B","C","D"]), Set(group.map(\.critical)).count==1,
                      Set(group.map(\.distractingCapture)).count==1 else { throw ChessFailure.invalid("条件不完整") }
                for p in group { try validate(p,check:checks.first{$0.id==p.id}) }
                valid += group
            } catch { issues.append("\(family.title)：\(error.localizedDescription)") }
        }
        let transfer=catalog.positions.filter{$0.family=="transfer"}
        do {
            guard transfer.count==4, transfer.filter({!$0.answers.isEmpty}).count==2 else { throw ChessFailure.invalid("延时题应有两题一步杀、两题无一步杀") }
            for p in transfer { try validate(p,check:checks.first{$0.id==p.id}) }; valid += transfer
        } catch { issues.append("延时复测：\(error.localizedDescription)") }
        if Set(valid.map{ReforgeRules.key($0.fen)}).count != valid.count { return ([],["题库包含重复局面"]) }
        return (valid,issues)
    }
}
