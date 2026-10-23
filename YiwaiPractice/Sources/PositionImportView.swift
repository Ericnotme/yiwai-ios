import SwiftUI
import UniformTypeIdentifiers

struct PositionImportView: View {
    @EnvironmentObject private var game: GameController
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editing: Bool
    @State private var format = "fen"
    @State private var text = ""
    @State private var error: String?
    @State private var imported: GameRecord?
    @State private var filePicker = false
    @State private var showImported = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("导入类型",selection:$format) { Text("FEN 局面").tag("fen"); Text("PGN 棋谱").tag("pgn") }.pickerStyle(.segmented).accessibilityIdentifier("importFormat")
                    Text(format == "fen" ? "粘贴完整六字段 FEN；包含轮次、易位、过路兵与回合计数。" : "粘贴单盘 PGN（最多 200 KB、600 半回合）。回放主线，原始注释和变例原文保留在时间胶囊中。")
                    TextEditor(text:$text).font(.body.monospaced()).frame(height:180).focused($editing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(format == "fen" ? "FEN 局面" : "PGN 棋谱").accessibilityIdentifier("importText")
                    Button("选择文件") { filePicker = true }.accessibilityIdentifier("importFile")
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("importError") }
                    Button("导入并打开",action:importNow).accessibilityIdentifier("confirmImport")
                } footer: { Text("导入记录仅保存在本机，分析使用本机 Stockfish。独立局面不计算整局准确度。") }
            }.navigationTitle("导入局面 / 棋谱").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("导入",action:importNow).accessibilityIdentifier("importToolbar") }
                    ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("收起键盘") { editing = false } }
                }
                .onChange(of:format) { _,_ in error = nil }
                .navigationDestination(isPresented:$showImported) { if let imported { GameReviewView(record:imported) } }
                .fileImporter(isPresented:$filePicker,allowedContentTypes:[.plainText,UTType(filenameExtension:"fen") ?? .data,UTType(filenameExtension:"pgn") ?? .data]) { result in
                    do {
                        let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
                        guard size <= (format == "fen" ? 512 : 200000) else { throw ChessFailure.invalid("文件过大：FEN 最多 512 字节，PGN 最多 200 KB。") }
                        text = try String(contentsOf:url,encoding:.utf8); error = nil
                    } catch { self.error = error.localizedDescription }
                }
        }
    }
    private func importNow() {
        do { imported = try game.importPosition(text,format:format); editing = false; error = nil; showImported = true }
        catch { self.error = error.localizedDescription }
    }

}
