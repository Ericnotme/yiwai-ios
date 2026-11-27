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
                VStack(alignment:.leading,spacing:28) {
                    VStack(alignment:.leading,spacing:14) {
                        HStack {
                            YiwaiEyebrow(text:"弈外 · SECOND LOOK")
                            Spacer()
                            Image(systemName:"leaf").foregroundStyle(Palette.sage).accessibilityHidden(true)
                        }
                        Text("留一点时间，\n把一步棋看清。")
                            .font(.system(.largeTitle,design:.serif).weight(.regular))
                            .lineSpacing(5).fixedSize(horizontal:false,vertical:true)
                            .accessibilityIdentifier("learningHomeTitle")
                        Text("从一个小问题开始。先想一想，再看看棋盘上的证据。")
                            .font(.body).foregroundStyle(Palette.muted).lineSpacing(4)
                    }.padding(.top,12)
                    NavigationLink { FortressLabView() } label: {
                        VStack(alignment:.leading,spacing:14) {
                            YiwaiEyebrow(text:"从这里开始")
                            Text("不败空间").font(.system(.title,design:.serif).weight(.medium)).foregroundStyle(Palette.ink)
                            Text("四章，16 道小题。\n换个条件，再看一步。")
                                .font(.body).foregroundStyle(Palette.muted).lineSpacing(4)
                            HStack {
                                Text("进入课程").font(.body.weight(.medium))
                                Spacer()
                                Image(systemName:"arrow.right")
                            }.foregroundStyle(Palette.coral).padding(.top,6)
                        }.multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading).yiwaiSurface().contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("fortressEntry")
                    VStack(alignment:.leading,spacing:16) {
                        Text("从自己的棋局里，找一个为什么")
                            .font(.system(.title3,design:.serif).weight(.medium))
                        VStack(spacing:18) {
                            NavigationLink { PersonalStudyHome() } label: {
                                YiwaiLinkRow(title:"回看我的一步棋",detail:"导入 PGN，留下自己的判断。",symbol:"text.book.closed")
                            }.accessibilityIdentifier("openPersonalStudy")
                            Divider().overlay(Palette.rule)
                            Button {
                                do { demo = try LearningDemoModel(exposureStore:decisions); error = nil }
                                catch { self.error = error.localizedDescription }
                            } label: {
                                YiwaiLinkRow(title:"先用示例走一遍",detail:"无需准备棋谱，示例不计个人进度。",symbol:"play.circle")
                            }.accessibilityIdentifier("startLearningDemo")
                        }.buttonStyle(.plain).yiwaiSurface()
                    }
                    VStack(alignment:.leading,spacing:16) {
                        HStack(alignment:.firstTextBaseline) {
                            Text("留在这里的思路").font(.system(.title3,design:.serif).weight(.medium))
                            Spacer()
                            Text("\(game.records.count) 盘棋谱").font(.caption).foregroundStyle(Palette.muted)
                        }
                        VStack(spacing:18) {
                            NavigationLink { DecisionListView() } label: {
                                YiwaiLinkRow(title:"理由与复习",detail:"回到当时的想法，到期再试一题。",symbol:"arrow.counterclockwise")
                            }.accessibilityIdentifier("homeReviews")
                            Divider().overlay(Palette.rule)
                            NavigationLink { LearningPatternView() } label: {
                                YiwaiLinkRow(title:"寻找相似的机会",detail:"看看自己的棋谱里，哪些细节再次出现。",symbol:"magnifyingglass")
                            }.accessibilityIdentifier("homePatterns")
                            Divider().overlay(Palette.rule)
                            NavigationLink { TimeCapsuleView() } label: {
                                YiwaiLinkRow(title:"时间胶囊",detail:"把棋局、备注和练习记录一起带走。",symbol:"archivebox")
                            }.accessibilityIdentifier("homeTimeCapsule")
                        }.buttonStyle(.plain).yiwaiSurface()
                        Text("\(game.records.count) 盘本机棋谱 · \(decisions.data.items.count) 处个人复习项")
                            .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("homeCounts")
                    }
                    Button { importing = true } label: {
                        Label("导入棋谱或局面 · PGN / FEN",systemImage:"square.and.arrow.down")
                    }.buttonStyle(YiwaiActionStyle(primary:false)).accessibilityIdentifier("homeImport")
                    NavigationLink { ConditionStudyHome() } label: {
                        YiwaiLinkRow(title:"换个条件，试试判断",detail:"可自愿参加的 12 局面对照练习。",symbol:"square.on.square")
                    }.buttonStyle(.plain).accessibilityIdentifier("openConditionStudy")
                    DisclosureGroup("关于这段学习旅程") {
                        Text("棋谱学习目前聚焦「漏走一步将死」，有 5 道经棋规核验的白方新局面。证据不足或题库用尽时会说明。练习记录帮助你回看思路，不是棋力或 Elo 评分。示例与个人记录分开保存。")
                            .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top,8)
                    }.font(.subheadline).tint(Palette.sage)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("关于弈外、隐私与开源许可") { about = true }
                        .font(.caption).foregroundStyle(Palette.muted).frame(minHeight:44).accessibilityIdentifier("learningAbout")
                }.padding(.horizontal,24).padding(.bottom,28).frame(maxWidth:640).frame(maxWidth:.infinity)
            }.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("学习").navigationBarTitleDisplayMode(.inline)
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
