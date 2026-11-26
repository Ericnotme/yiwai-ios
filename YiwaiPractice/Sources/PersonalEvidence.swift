import Foundation
import CryptoKit

struct PersonalProbe: Codable {
    struct Score: Codable { let type:String; let value:Int }
    let evaluation:ReviewEvaluation
    let rawScore:Score // UCI side-to-move perspective; never treat a mate as centipawns.
    let elapsedMS:Int; let stopReason:String; let budgetMS:Int; let history:[String]; let initialFEN:String
    var engine:String = GameReviewReport.engineName
    var settings:String = "Hash=32 MiB; Threads=1 (lite single); Skill Level=20; MultiPV=1; fresh worker per probe"
    var scorePerspective:String = "rawScore: side to move; evaluation.cp: white only when rawScore.type=cp; mate: winner and distance"
    var recordedAt:Date = Date()
    enum CodingKeys:String,CodingKey { case evaluation,rawScore,elapsedMS,stopReason,budgetMS,history,initialFEN,engine,settings,scorePerspective,recordedAt }
    init(evaluation:ReviewEvaluation,rawScore:Score,elapsedMS:Int,stopReason:String,budgetMS:Int,history:[String],initialFEN:String) {
        self.evaluation=evaluation;self.rawScore=rawScore;self.elapsedMS=elapsedMS;self.stopReason=stopReason;self.budgetMS=budgetMS;self.history=history;self.initialFEN=initialFEN
    }
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        evaluation=try c.decode(ReviewEvaluation.self,forKey:.evaluation);rawScore=try c.decode(Score.self,forKey:.rawScore)
        elapsedMS=try c.decode(Int.self,forKey:.elapsedMS);stopReason=try c.decode(String.self,forKey:.stopReason);budgetMS=try c.decode(Int.self,forKey:.budgetMS)
        history=try c.decode([String].self,forKey:.history);initialFEN=try c.decode(String.self,forKey:.initialFEN)
        engine=try c.decodeIfPresent(String.self,forKey:.engine) ?? engine;settings=try c.decodeIfPresent(String.self,forKey:.settings) ?? settings
        scorePerspective=try c.decodeIfPresent(String.self,forKey:.scorePerspective) ?? scorePerspective;recordedAt=try c.decodeIfPresent(Date.self,forKey:.recordedAt) ?? recordedAt
    }
}
struct PersonalBranch:Codable { let history:[String]; let fen:String; let answers:[String]; let replaced:String; let replacement:String; let replacementSAN:String;let critical:String;let criticalSAN:String;let criticalReplies:[String];let criticalOutcome:String
    var outcomeLabel:String { ["stalemate":"逼和","draw":"和棋","check with legal replies":"将军，但有合法应将","ongoing":"非终局，仍可应对"][criticalOutcome] ?? criticalOutcome }
}
struct PersonalPosition:Codable,Identifiable {
    let id:String;let version:Int;let fen:String;let history:[String];let answers:[String];let source:String;let license:String
    var probes:[PersonalProbe]=[]
    var catalogProof:ConditionPosition?;var catalogCheck:ConditionEngineCheck?
}
struct PersonalAnswer:Codable {
    let submissionID:UUID;let choice:String;let candidates:String;let reason:String;let at:Date;let context:String;let exclusions:[String]
}
struct PersonalTrial:Codable,Identifiable {
    let id:UUID;let submissionID:UUID;let position:PersonalPosition;let kind:String
    var shownAt:Date?;var hintAt:Date?;var first:PersonalAnswer?;var exclusions:[String]=[]
    var candidates="";var reason=""
    var correct:Bool? { first.map { position.answers.isEmpty ? $0.choice=="none" : position.answers.contains($0.choice) } }
}
struct PersonalRound:Codable,Identifiable {
    let id:UUID;let kind:String;let seed:UInt64;let startedAt:Date
    var trials:[PersonalTrial];var feedbackAt:Date?
    var current:PersonalTrial? { feedbackAt==nil ? trials.first{$0.first==nil} : nil }
}
struct PersonalAttempt:Codable { let ply:Int;let history:[String];let probes:[PersonalProbe];let outcome:String;let at:Date }
struct PersonalRecollection:Codable { let text:String;let at:Date;let context:String }
struct PersonalCase:Codable,Identifiable {
    var id=UUID();let game:GameRecord;let gameKey:String;let side:String;let demonstration:Bool;let createdAt:Date
    var status="pending";var scan:GamePatternScan?;var attempts:[PersonalAttempt]=[];var evidence:MateEvidence?;var branch:PersonalBranch?
    var rounds:[PersonalRound]=[];var dueAt:Date?;var demoTimeAdvancedAt:Date?;var recollections:[PersonalRecollection]=[];var hypothesisCorrection:String?;var explanationVersion=1
    static let initialHypothesis = "可能需要再次检查候选将军着以及对手所有合法应将。这只是棋理假说，单盘棋无法说明你当时为何这样走；可纠正或不认同。"
    var hypothesisText:String? = Self.initialHypothesis
    var hypothesis:String { hypothesisText ?? Self.initialHypothesis }
    var active:PersonalRound? { rounds.last(where:{$0.feedbackAt==nil}) }
}
struct PersonalArchive:Codable {
    var schemaVersion=1;var algorithm="standard-history-missed-mate-one-v1";var clockOrigin="device clock"
    var cases:[PersonalCase]=[]
}
final class PersonalRules {
    let engine:ChessEngine
    init(cancellation:SearchCancellation?=nil)throws {engine=try ChessEngine(cancellation:cancellation)}
    static let demoPGN="""
    [Event "Yiwai constructed complete example"]
    [Site "Local demonstration"]
    [White "Example white"]
    [Black "Example black"]
    [Result "1-0"]

    1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qf3 Nxe4 5. Qxf7# 1-0
    """
    func parse(_ pgn:String,side:String)throws->GameRecord {
        guard pgn.utf8.count<=200000 else {throw ChessFailure.invalid("最多 200 KB，单盘 PGN")}
        struct Imported:Decodable {let initialFen:String;let moves:[String];let headers:[String:String]}
        let p:Imported=try engine.call("personalImport",[pgn,side])
        return GameRecord(initialFEN:p.initialFen,moves:p.moves,human:side,ending:"saved",source:"pgn",importedHeaders:p.headers,originalPGN:pgn)
    }
    func branches(_ evidence:MateEvidence)throws->[PersonalBranch] {
        struct Result:Decodable {let branches:[PersonalBranch]}
        return try engine.call("personalBranches",[evidence.history,evidence.answers.first ?? ""],as:Result.self).branches
    }
    struct Validation:Decodable {let fen:String;let answers:[String];let legal:[String]}
    func validate(history:[String],pv:[String]=[])throws->Validation {try engine.call("personalValidate",[history,pv])}
    func stable(_ probes:[PersonalProbe],history:[String],answers:[String])throws->Bool {
        guard probes.count==2,probes.map(\.budgetMS)==[450,1400] else {return false}
        for p in probes {
            guard p.history==history,p.initialFEN==ChessEngine.initialFEN,p.engine==GameReviewReport.engineName,
                  p.evaluation.depth>0,!p.evaluation.terminal,!p.stopReason.isEmpty,p.elapsedMS>=0 else {return false}
            let v=try validate(history:history,pv:p.evaluation.pv)
            guard v.answers==answers.sorted(),let best=p.evaluation.best,p.evaluation.pv.first==best,v.legal.contains(best) else {return false}
            let mateOne=p.rawScore.type=="mate" && p.rawScore.value==1
            guard mateOne == !answers.isEmpty, !mateOne || answers.contains(best) else {return false}
            if p.rawScore.type=="cp" {let sign=v.fen.split(separator:" ")[1]=="w" ? 1.0 : -1.0;guard p.evaluation.mate==nil,p.evaluation.cp.isFinite,p.evaluation.cp==Double(p.rawScore.value)*sign else{return false}}
            else if p.rawScore.type=="mate" {let side=String(v.fen.split(separator:" ")[1]);let winner=p.rawScore.value>0 ? side:(side=="w" ? "b":"w");guard p.evaluation.mate==abs(p.rawScore.value),p.evaluation.winner==winner else{return false}}
            else {return false}
        }
        let a=probes[0].rawScore,b=probes[1].rawScore
        return a.type==b.type && (a.type=="mate" ? a.value==b.value : abs(a.value-b.value)<=75)
    }
    // Conservative novelty filter, not a claim about a person's lifetime exposure.
    // Compare every board symmetry, with/without swapping colors; <=4 changed squares
    // excludes adjacent moves and close tactical clones. Exact identity still keeps FEN state.
    static func near(_ lhs:String,_ rhs:String)->Bool {
        func board(_ fen:String)->[Character]? {
            var result:[Character]=[]
            for c in fen.split(separator:" ").first ?? "" {if c=="/"{continue};if let n=c.wholeNumberValue{result += Array(repeating:".",count:n)}else{result.append(c)}}
            return result.count==64 ? result:nil
        }
        guard let a=board(lhs),let b=board(rhs) else{return true}
        for flip in [false,true] {for rotation in 0..<4 {for swap in [false,true] {
            var distance=0
            for y in 0..<8 {for x in 0..<8 {
                var u=flip ? 7-x:x,v=y
                for _ in 0..<rotation {let old=u;u=7-v;v=old}
                var p=b[v*8+u]
                if swap && p != "." {let s=String(p);p=Character(s==s.uppercased() ? s.lowercased():s.uppercased())}
                if a[y*8+x] != p {distance += 1}
            }}
            if distance<=4{return true}
        }}}
        return false
    }
}
