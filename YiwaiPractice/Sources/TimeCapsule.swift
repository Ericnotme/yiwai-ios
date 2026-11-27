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
    let conditionStudy: ConditionArchive?
    let personalEvidence: PersonalArchive?
    let fortressProgress: FortressProgressArchive?
    let fortressLessons: FortressCourseCatalog?

    static func build(games: [GameRecord], notebook: [ReviewEntry], date: Date = Date(), appVersion: String, decisions: DecisionArchive? = nil, conditionStudy: ConditionArchive? = nil, personalEvidence: PersonalArchive? = nil, fortressProgress: FortressProgressArchive? = nil, fortressLessons: FortressCourseCatalog? = nil) throws -> Self {
        let engine = try ChessEngine()
        let pgn = try games.map { record in
            // An unplayed normal game also needs FEN headers so it can be re-imported.
            var portable = record
            if portable.moves.isEmpty && portable.importedHeaders == nil {
                portable.importedHeaders = ["Event":"Yiwai local computer game","White":record.human == "w" ? "Player" : "Seed 0.2","Black":record.human == "b" ? "Player" : "Seed 0.2"]
            }
            return PGN(recordID:record.id,mainlinePGN:try engine.game(portable).pgn)
        }
        return Self(format:"yiwai-local-time-capsule",schemaVersion:6,exportedAt:date,appVersion:appVersion,
            readme:"UTF-8 JSON；schema6 的 fortressProgress 保存本机不败空间作答，每条包含题目版本及当时完整定义、首答、最近作答和次数；fortressLessons 是当前课程定义。示例空间不导出个人课程记录。首答不因重做覆盖，已作答不代表已掌握；旧版不存在的记录不会补造。personalEvidence 包含个人原始 PGN、确认执棋方、逐步规则扫描、引擎双预算及原始分值类型/视角/完整 PV、合法替代分支、明确标注的匹配题、随机题序、不可覆盖首答、提示曝光、用户反馈后回忆与修正、实际到期时间及示例模拟标记。该数据不证明心理因果或学习效果。所有时间为自 1970-01-01 UTC 起的秒数。games 包含本机棋谱、FEN、走法、原始 PGN（originalPGN）、个人备注及已保存分析。gamePGN 是对应的标准主线 PGN，保留 FEN 起始局面；主线导出不含原始变例或注释，请查 originalPGN。旧版导入未保留的原文无法恢复。notebook 是错题本记录及备注，lessons 是本版本内置题目完整定义。decisions.scans 包含已确认执棋方、棋谱指纹、检测版本及逐处规则证据，notes.evidence 连接已选择的证据。notes.recollections 保留用户在看过反馈后追加的事后回忆或主动跳过，原始记录不被覆盖。sessions.demonstration 标识交互示例，示例提交不计个人进度；seen.source 标识示例曝光。decisions 包含原决策、用户原话及记录时机、标签修改、题目版本和题源、已展示局面、首次答案、提示时间、完成时间、到期时间及独立通过次数、针对性练习与独立复测的区分；它的 schemaVersion 单独管理。clockOrigin 说明设备时间或测试注入时间。conditionStudy 独立管理 schemaVersion，保存实验题目版本与合法 PGN 证明、引擎复核、随机种子及实际题序、首次提交、候选着/威胁自述、演示/已见/提示排除理由、暂停时间、反馈及实际到期时间、反馈后重试与补记。条件记录不是注意力或心理测量。完整导出包含答案，开始导出前需结束未完成的条件练习。旧记录不存在的数据不会补造。此文件是导出快照，不会自动更新；当前 App 暂无整包恢复入口。未提供云备份、加密或长期保存保证。请自行保管并定期检查副本。",
            games:games,gamePGN:pgn,notebook:notebook,lessons:Lesson.all,decisions:decisions,conditionStudy:conditionStudy,personalEvidence:personalEvidence,fortressProgress:fortressProgress,fortressLessons:fortressLessons)
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }
}
