import Foundation
import WebKit
import SwiftUI

struct CoachExplanation: Codable {
    let theme: String; let summary: String; let why: String; let missed: String
    let habit: String; let boundary: String; let bestSAN: [String]; let playedSAN: [String]
}
struct ReviewEvaluation: Codable {
    let cp: Double; let win: Double; let depth: Int; let terminal: Bool; let draw: Bool
    let mate: Int?; let winner: String?; let best: String?; let pv: [String]; let nodes: Int; let legalCount: Int
    var label: String {
        if draw { return "和棋" }
        if let mate { return "\(winner == "w" ? "白" : "黑")方 M\(mate)" }
        return String(format:"白方 %+.2f",cp/100)
    }
}
struct ReviewedMove: Codable, Identifiable {
    let ply: Int; let color: String; let san: String; let number: Int
    let loss: Double; let rawLoss: Double; let accuracy: Double; let weight: Double; let category: String; let forced: Bool
    let bestPV: [String]; let playedPV: [String]; let coach: CoachExplanation
    var id: Int { ply }
    var label: String { ["best":forced ? "唯一合法走法" : "本次首选","excellent":"优秀","good":"稳健","inaccuracy":"不精确","mistake":"失误","blunder":"严重失误"][category] ?? "查看变化" }
    var moveLabel: String { "\(number)\(color == "w" ? "." : "…") \(san)" }
}
struct GameReviewReport: Codable {
    static let metricID = "knight-room-review-v1"
    static let engineName = "Stockfish 19 · lite single"
    let metric: String; let engine: String; let initialFEN: String; let history: [String]; let duration: Int
    let gameComplete: Bool; let evaluations: [ReviewEvaluation]; let entries: [ReviewedMove]
    let white: Double?; let black: Double?; let minDepth: Int; let maxDepth: Int
    func matches(_ record: GameRecord) -> Bool {
        metric == Self.metricID && engine == Self.engineName && initialFEN == record.initialFEN && history == record.moves &&
        entries.count == history.count && evaluations.count == history.count+1 && [450,1400].contains(duration) &&
        entries.enumerated().allSatisfy { $0.element.ply == $0.offset+1 && $0.element.playedPV.first == history[$0.offset] } &&
        evaluations.allSatisfy { $0.win.isFinite && (0...100).contains($0.win) && ($0.terminal || $0.depth > 0) } &&
        [white,black].compactMap { $0 }.allSatisfy { $0.isFinite && (0...100).contains($0) }
    }
}

/// A nonpersistent, network-blocked WebKit runtime only for the bundled WASM worker.
/// All product screens and the chessboard remain native SwiftUI.
@MainActor final class StockfishReviewEngine: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private var loaded: CheckedContinuation<Void,Error>?
    private var cancelled = false
    private var runID = UUID().uuidString
    var onProgress: ((Int,Int) -> Void)?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame:.zero,configuration:configuration)
        super.init()
        webView.navigationDelegate = self
        configuration.userContentController.add(self,name:"reviewProgress")
    }
    func analyze(_ record: GameRecord, duration: Int) async throws -> GameReviewReport {
        guard !cancelled else { throw CancellationError() }
        func resource(_ name: String,_ ext: String) throws -> String {
            guard let url = Bundle.main.url(forResource:name,withExtension:ext) else { throw ChessFailure.invalid("缺少本地分析资源：\(name)") }
            return try String(contentsOf:url,encoding:.utf8)
        }
        let scripts = try [resource("chess","js"),resource("game-review","js"),resource("stockfish-review","js")]
        let policy = "default-src 'none'; script-src 'unsafe-inline' 'wasm-unsafe-eval' blob:; worker-src blob:; connect-src data:;"
        let html = "<!doctype html><meta http-equiv='Content-Security-Policy' content=\"\(policy)\"><title>Local chess analysis</title>" + scripts.map { "<script>\($0.replacingOccurrences(of:"</script",with:"<\\/script"))</script>" }.joined()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void,Error>) in
            loaded = continuation
            webView.loadHTMLString(html,baseURL:nil)
        }
        guard !cancelled, !Task.isCancelled else { throw CancellationError() }
        guard let wasmURL = Bundle.main.url(forResource:"stockfish-19-lite-single",withExtension:"wasm",subdirectory:"Stockfish"),
              let sourceURL = Bundle.main.url(forResource:"stockfish-19-lite-single",withExtension:"js",subdirectory:"Stockfish") else { throw ChessFailure.invalid("Stockfish 尚未随此构建提供；不能用 Seed 分值代替准确度") }
        let source = try String(contentsOf:sourceURL,encoding:.utf8), wasm = try Data(contentsOf:wasmURL).base64EncodedString()
        let input: [String:Any] = ["initialFEN":record.initialFEN,"history":record.moves,"duration":duration,"gameComplete":record.ending=="resigned","runID":runID]
        let result = try await webView.callAsyncJavaScript("return await window.YiwaiStockfish.run(input, source, wasm);",arguments:["input":input,"source":source,"wasm":wasm],in:nil,contentWorld:.page)
        guard !cancelled, !Task.isCancelled else { throw CancellationError() }
        guard let json = result as? String, let data = json.data(using:.utf8) else { throw ChessFailure.invalid("分析结果为空") }
        let report = try JSONDecoder().decode(GameReviewReport.self,from:data)
        guard report.matches(record) else { throw ChessFailure.invalid("分析结果与棋谱不匹配") }
        return report
    }
    func cancel() {
        cancelled = true
        loaded?.resume(throwing:CancellationError()); loaded = nil
        webView.evaluateJavaScript("window.YiwaiStockfish?.stop()",completionHandler:nil)
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName:"reviewProgress")
        webView.navigationDelegate = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loaded?.resume(throwing:error); loaded = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loaded?.resume(throwing:error); loaded = nil }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loaded?.resume(throwing:ChessFailure.invalid("本地分析进程结束，请重试")); loaded = nil }
    func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
        guard !cancelled, let data = message.body as? [String:Any], data["id"] as? String == runID,
              let completed = data["completed"] as? Int, let total = data["total"] as? Int else { return }
        onProgress?(completed,total)
    }
    func webView(_ webView: WKWebView,decidePolicyFor navigationAction: WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }
}
struct ReviewEngineHost: UIViewRepresentable {
    let engine: StockfishReviewEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ uiView: WKWebView,context: Context) {}
}
