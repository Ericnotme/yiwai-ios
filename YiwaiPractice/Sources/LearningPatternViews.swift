import SwiftUI

struct LearningPatternView: View {
    @EnvironmentObject private var game: GameController
    @EnvironmentObject private var decisions: DecisionStore
    var body: some View {
        List {
            Section("这版明确支持什么") {
                Text("只查漏走一步将死：先确认你执哪一方，再用本机棋规逐步检查。不会分析其他错误类型，也不推断当时心理。")
                Text("同一棋谱重复导入不凑次数；至少两盘不同棋局、两个不同局面才显示重复证据。没有发现不等于没有问题。").font(.caption)
            }
            Section("已检查的本机棋谱") {
                let summary = decisions.patternSummary(games:game.records)
                Text(summary.label).font(.headline).accessibilityIdentifier("patternSummary")
                Text("已检查 \(summary.scans.count) 盘；证据来自你确认的执棋方。选择练习前可更正执棋方并重新检查。").font(.caption)
            }
            if game.records.isEmpty { Text("先在棋谱页手动导入一盘 PGN。").accessibilityIdentifier("patternEmpty") }
            Section("选择棋谱并确认执棋方") {
                ForEach(game.records) { record in
                    NavigationLink { GamePatternView(record:record) } label: {
                        VStack(alignment:.leading) {
                            Text(record.title)
                            Text(record.importedHeaders?["Event"] ?? record.created.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                        }
                    }.accessibilityIdentifier("pattern-game-\(record.id)")
                }
            }
        }.navigationTitle("从棋谱找练习").navigationBarTitleDisplayMode(.inline)
    }
}
struct GamePatternView: View {
    let record: GameRecord
    @EnvironmentObject private var decisions: DecisionStore
    @EnvironmentObject private var game: GameController
    @StateObject private var scanner = PatternScanController()
    @State private var side = ""
    @State private var error: String?
    @State private var itemID: UUID?
    @State private var showPlan = false
    private var scan: GamePatternScan? { decisions.data.scans?.first { $0.gameKey == MatePatternDetector.gameKey(record) } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("只检查：漏走当步可一步将死的着法").font(.headline)
                Picker("这盘你执哪一方",selection:$side) {
                    Text("请选择").tag(""); Text("我执白").tag("w"); Text("我执黑").tag("b")
                }.pickerStyle(.segmented).accessibilityIdentifier("patternSide").disabled(scanner.busy)
                Text("不会根据 PGN 姓名猜测你的身份；执棋方选错会分析到对手，请确认后开始。").font(.caption)
                if scanner.busy {
                    ProgressView("沿棋谱逐步核验…")
                    Button("取消本次检查") { scanner.cancel() }.accessibilityIdentifier("cancelPatternScan")
                } else {
                    Button("在本机检查这盘棋") { error = nil; scanner.scan(record,side:side,at:decisions.now) }
                        .buttonStyle(.borderedProminent).disabled(side.isEmpty).accessibilityIdentifier("scanPattern")
                }
                if let error = error ?? scanner.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("patternError") }
                if let scan {
                    Text("已检查\(scan.side == "w" ? "白" : "黑")方 \(scan.examined) 步；其中 \(scan.opportunities) 步可一步将死，\(scan.misses) 步未采用当步将死着。")
                        .accessibilityIdentifier("scanSummary")
                    Text(decisions.patternSummary(games:game.records).label).font(.headline).accessibilityIdentifier("gamePatternSummary")
                    if scan.evidence.isEmpty {
                        Text("这盘未发现此类型。不会用无关棋题替你诊断弱点；其他类型暂不支持。").accessibilityIdentifier("noPatternEvidence")
                    }
                    ForEach(scan.evidence.prefix(2)) { evidence in
                        VStack(alignment:.leading,spacing:12) {
                            Text("证据：第 \(evidence.moveNumber) 回合\(evidence.side == "w" ? "白" : "黑")方").font(.headline)
                            if let frame = try? ChessEngine().frames(fen:evidence.fen).first { GameBoard(frame:frame) }
                            Text(evidence.explanation).accessibilityIdentifier("patternEvidenceExplanation")
                            if !evidence.replyExamples.isEmpty { Text("实际走法后，对方可走：\(evidence.replyExamples.joined(separator:"、"))。").font(.caption) }
                            Text("练习将针对寻找将军并排除所有应将。这里只呈现棋规证据，不代写你的理由。").font(.caption)
                            Button(decisions.plan(for:evidence) == nil ? "用这处证据建立练习" : "继续这处练习与复测") {
                                do { itemID = try decisions.createEvidencePlan(evidence,game:record).id; showPlan = true; error = nil }
                                catch { self.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("trainEvidence-\(evidence.ply)")
                        }.padding().background(.white,in:RoundedRectangle(cornerRadius:12))
                    }
                    if scan.evidence.count > 2 { Text("只邀请前两处练习，其余证据保留在本地导出；同盘多次机会不算多盘重复。").font(.caption) }
                }
            }.padding(16).frame(maxWidth:560)
        }.background(Palette.paper).navigationTitle("棋谱证据").navigationBarTitleDisplayMode(.inline)
        .onChange(of:scanner.completionID) { _,_ in
            if let result = scanner.result {
                do { try decisions.saveScan(result,game:record) } catch { self.error = error.localizedDescription }
            }
        }
        .onDisappear { scanner.cancel() }
        .navigationDestination(isPresented:$showPlan) { if let itemID { DecisionDetailView(itemID:itemID) } }
    }
}
