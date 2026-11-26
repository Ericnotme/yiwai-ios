import SwiftUI

struct LearningHomeView: View {
    @EnvironmentObject private var game: GameController
    @EnvironmentObject private var decisions: DecisionStore
    @State private var importing = false
    @State private var about = false
    @State private var demo: LearningDemoModel?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text("把一处失误，\n变成下次的检查").font(.largeTitle.weight(.semibold)).accessibilityIdentifier("learningHomeTitle")
                    Text("弈外 · Second Look Chess").font(.subheadline).foregroundStyle(Palette.sage)
                    Text("自己的棋局 → 可核验的证据 → 自己的理由 → 少量练习 → 到期换个局面再试。")
                    NavigationLink {
                        FortressLabView()
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.title2).foregroundStyle(Palette.sage)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("不败空间").font(.headline).foregroundStyle(Palette.ink)
                                Text("预测 · 攻防 · 反例").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.sage)
                        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.accessibilityIdentifier("fortressEntry")
                    NavigationLink { PersonalStudyHome() } label: {
                        VStack(alignment:.leading,spacing:8) {Text("体验一局 / 导入我的 PGN").font(.headline);Text("本地引擎证据 → 合法分支复答 → 匹配练习 → 到期未见题。仅支持一步将杀，原因是假说，可纠正。").font(.subheadline)}
                    }.padding(18).background(.white,in:RoundedRectangle(cornerRadius:18)).accessibilityIdentifier("openPersonalStudy")
                    VStack(alignment:.leading,spacing:12) {
                        Text("先体验一次完整过程").font(.title3.weight(.semibold))
                        Text("无需账号或私人棋谱。用明确标注的构造示例走完流程，示例成绩不计个人进度。")
                        Button("用示例走完一次") {
                            do { demo = try LearningDemoModel(exposureStore:decisions); error = nil }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).frame(minHeight:44).accessibilityIdentifier("startLearningDemo")
                    }.padding(18).background(.white,in:RoundedRectangle(cornerRadius:18))
                    VStack(alignment:.leading,spacing:14) {
                        Text("从自己的棋局开始").font(.title3.weight(.semibold))
                        Button("导入我的 PGN / FEN") { importing = true }.buttonStyle(.bordered).frame(minHeight:44).accessibilityIdentifier("homeImport")
                        NavigationLink("检查棋谱中的同类机会") { LearningPatternView() }.frame(minHeight:44).accessibilityIdentifier("homePatterns")
                        NavigationLink("回看理由与到期复习") { DecisionListView() }.frame(minHeight:44).accessibilityIdentifier("homeReviews")
                        Text("\(game.records.count) 盘本机棋谱 · \(decisions.data.items.count) 处个人复习项").font(.caption).accessibilityIdentifier("homeCounts")
                        NavigationLink("时间胶囊 · 完整本地导出") { TimeCapsuleView() }.frame(minHeight:44).accessibilityIdentifier("homeTimeCapsule")
                    }
                    NavigationLink { ConditionStudyHome() } label: { VStack(alignment:.leading,spacing:8) { Text("改变条件、发现盲区 · 实验").font(.headline); Text("自愿对照 12 个局面，统一反馈后再等 24 小时换题复测。").font(.subheadline) } }.padding(18).background(.white,in:RoundedRectangle(cornerRadius:18)).accessibilityIdentifier("openConditionStudy")
                    Text("棋谱学习当前只支持「漏走一步将死」；5 道经棋规核验的白方新局面，属于同一个主题。证据不足或题库用尽会明确说明。练习表现不等于棋力或 Elo 提升。").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("关于弈外、隐私与开源许可") { about = true }.frame(minHeight:44).accessibilityIdentifier("learningAbout")
                }.padding(20).frame(maxWidth:640).frame(maxWidth:.infinity)
            }.background(Palette.paper).navigationTitle("学习").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$importing) { PositionImportView() }
            .sheet(isPresented:$about) { AboutView() }
            .fullScreenCover(item:$demo) { model in LearningDemoView(model:model) }
        }
    }
}
struct LearningDemoView: View {
    @ObservedObject var model: LearningDemoModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing:0) {
            Text("示例空间 · 构造棋谱 · \(model.advanced ? "已模拟到期" : "非个人棋局")\n所有示例结果不计个人进度")
                .font(.caption.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity).padding(10).background(Palette.sage.opacity(0.15)).accessibilityIdentifier("demoBanner")
            NavigationStack {
                LearningDemoWorkspace(model:model,game:model.game,decisions:model.decisions)
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("结束示例") { dismiss() }.accessibilityIdentifier("closeLearningDemo") } }
            }
        }
        .environmentObject(model.game).environmentObject(model.decisions).environmentObject(model.notebook)
    }
}
private struct LearningDemoWorkspace: View {
    @ObservedObject var model: LearningDemoModel
    @ObservedObject var game: GameController
    @ObservedObject var decisions: DecisionStore
    @State private var error: String?
    var body: some View {
        List {
            Section("1 · 手动载入示例，再确认执棋方") {
                Text("示例 A、B 是两段不同的构造棋谱。各检查白方，才能看到两盘的重复证据；选黑方会得到不同结果。它们不是你的错误记录。")
                ForEach(model.samples) { sample in
                    VStack(alignment:.leading,spacing:10) {
                        Text(sample.title).font(.headline)
                        Text(sample.source).font(.caption)
                        if let id = model.sampleRecords[sample.id], let record = game.records.first(where:{$0.id == id}) {
                            NavigationLink("检查这盘示例") { GamePatternView(record:record) }.accessibilityIdentifier("demo-check-\(sample.id)")
                            DisclosureGroup("查看 PGN 与来源") { Text(sample.pgn).font(.caption.monospaced()).textSelection(.enabled); Text(sample.license).font(.caption) }
                        } else {
                            Button("载入这盘 PGN") { perform { _ = try model.importSample(sample) } }.accessibilityIdentifier("demo-import-\(sample.id)")
                        }
                    }.padding(.vertical,6)
                }
            }
            Section("2 · 看证据，保留自己的话") {
                Text(decisions.patternSummary(games:game.records).label).accessibilityIdentifier("demoPatternSummary")
                Text("检查后选择一处建立练习；在详情补记你现在的候选着和理由。补记明确标为看过反馈后的事后回忆，可跳过。")
                NavigationLink("打开示例理由与复习项") { DecisionListView() }.accessibilityIdentifier("demoReviews")
                if let sample = model.samples.first, model.sampleRecords[sample.id] != nil {
                    Button("再次导入示例 A，检查去重") { perform { _ = try model.importSample(sample,duplicate:true) } }.accessibilityIdentifier("demoDuplicate")
                    Text("重复导入不会增加重复证据的棋局数量。").font(.caption)
                }
            }
            Section("3 · 练一题，再在不同局面复测") {
                Text("先在复习项中完成针对性练习。真实个人复习从完成时起等 24 小时；下面仅推进示例时钟，方便体验。")
                Button("模拟来到下一次到期（仅示例）") { perform { try model.advanceToDue() } }
                    .disabled(!decisions.data.sessions.contains(where:{$0.kind == "practice" && $0.finished}) || decisions.data.sessions.contains(where:{!$0.finished}))
                    .accessibilityIdentifier("demoAdvance")
                Text("示例时间：\(decisions.now.formatted(date:.abbreviated,time:.shortened))").font(.caption)
                NavigationLink("继续示例复测与首答记录") { DecisionListView() }.accessibilityIdentifier("demoRetest")
            }
            Section("4 · 查看可带走的数据") {
                NavigationLink("导出这次示例记录") { TimeCapsuleView() }.accessibilityIdentifier("demoExport")
                Text("示例棋谱、理由和成绩保存在独立临时空间，结束后清理；导出明确保留示例和模拟时间标记。为避免把看过的题再称为新题，已展示局面会记入本机去重清单。不会上传。")
            }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("demoError") } }
        }.navigationTitle("走完一次学习循环").navigationBarTitleDisplayMode(.inline)
    }
    private func perform(_ body: () throws -> Void) { do { try body(); error = nil } catch { self.error = error.localizedDescription } }
}
