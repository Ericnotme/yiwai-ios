import Foundation

/// A self-contained, versioned snapshot. Never contacts a service or writes to the app's store.
struct TimeCapsule: Codable {
    struct PGN: Codable {
        let recordID: UUID
        let mainlinePGN: String
    }
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let readme: String
    let games: [GameRecord]
    let gamePGN: [PGN]
    let notebook: [ReviewEntry]
    let lessons: [Lesson]
    let decisions: DecisionArchive?

    static func build(games: [GameRecord], notebook: [ReviewEntry], date: Date = Date(), appVersion: String, decisions: DecisionArchive? = nil) throws -> Self {
        let engine = try ChessEngine()
        let pgn = try games.map { record in
            // An unplayed normal game also needs FEN headers so it can be re-imported.
            var portable = record
            if portable.moves.isEmpty && portable.importedHeaders == nil {
                portable.importedHeaders = ["Event":"Yiwai local computer game","White":record.human == "w" ? "Player" : "Seed 0.2","Black":record.human == "b" ? "Player" : "Seed 0.2"]
            }
            return PGN(recordID:record.id,mainlinePGN:try engine.game(portable).pgn)
        }
        return Self(format:"yiwai-local-time-capsule",schemaVersion:2,exportedAt:date,appVersion:appVersion,
            readme:"UTF-8 JSON；所有时间为自 1970-01-01 UTC 起的秒数。games 包含本机棋谱、FEN、走法、原始 PGN（originalPGN）、个人备注及已保存分析。gamePGN 是对应的标准主线 PGN，保留 FEN 起始局面；主线导出不含原始变例或注释，请查 originalPGN。旧版导入未保留的原文无法恢复。notebook 是错题本记录及备注，lessons 是本版本内置题目完整定义。decisions.scans 包含已确认执棋方、棋谱指纹、检测版本及逐处规则证据，notes.evidence 连接已选择的证据。decisions 包含原决策、用户原话及记录时机、标签修改、题目版本和题源、已展示局面、首次答案、提示时间、完成时间、到期时间及独立通过次数、针对性练习与独立复测的区分；它的 schemaVersion 单独管理。clockOrigin 说明设备时间或测试注入时间。旧记录不存在的数据不会补造。此文件是导出快照，不会自动更新；当前 App 暂无整包恢复入口。未提供云备份、加密或长期保存保证。请自行保管并定期检查副本。",
            games:games,gamePGN:pgn,notebook:notebook,lessons:Lesson.all,decisions:decisions)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }
}
