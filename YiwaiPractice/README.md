# 弈外 · iPhone 原生版

SwiftUI 原生页面 + JavaScriptCore 棋规，最低 iOS 17。本目录为 **0.4.0（10）** 的应用源码；构建步骤和许可证见仓库根目录的 `BUILDING.md`、`NOTICE.md`、`LICENSE`。复盘在非持久化 WebKit 中离线运行本地 Stockfish WASM。

## 可以做什么

- 离线人机对弈：选择执白或执黑、三档搜索时间、合法走子提示、升变、悔棋、暂停、认输；每步自动保存。
- 完整棋谱：继续历史棋局、逐步回放、跳转任一步、导出含结果和初始局面的 PGN。
- AI Coach：分别解释首选的作用和实际应手，逐步回放两条合法变化；支持取消、重新分析和完整报告缓存。
- 网站口径的双方准确度、局势曲线、关键失误；只有全部局面分析完毕才生成分数。
- 原有三个原创主题、九个练习局面，以及本地错题本和笔记。

对弈电脑继续使用原创 Seed 0.2，棋力未评级。复盘独立使用与网站相同的 Stockfish.js 19.0.0 lite single。AI Coach 是引擎证据与规则讲解，不是大模型对话。新增手动 FEN/PGN、本地时间胶囊和单主题学习闭环，见根目录 docs/learning-loop.md。没有付费 API、云同步或在线真人棋局辅助。

## 构建与测试

打开 `YiwaiPractice.xcodeproj`，使用 `YiwaiPractice` scheme。默认禁止签名，不自动申请证书或描述文件。无须 npm、CocoaPods、Swift Package 下载或网络服务。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project YiwaiPractice.xcodeproj -scheme YiwaiPractice \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -derivedDataPath build -jobs 1 -parallel-testing-enabled NO \
  -collect-test-diagnostics never test CODE_SIGNING_ALLOWED=NO
node --test scripts/engine-tests.cjs
node --test scripts/review-tests.cjs
```

增减源码文件后运行 `python3 scripts/generate-project.py` 更新工程。代码与资源：

- `Sources/GameModels.swift`：持久化、异步搜索、取消和防止过期结果落子、统一评分。
- `Sources/GameViews.swift`：原生对弈、整局回放、PGN 分享、教练与变化线。
- `Sources/StockfishReview.swift`：报告类型、本地 WebKit worker、进度、取消与网络隔离。
- `Sources/YiwaiApp.swift`、`Lessons.swift`、`Notebook.swift`：练习、导航、错题本、许可。
- `Resources/chess.js`：chess.js 1.4.0 棋规；`seed-engine.js`：原创搜索；`chess-bridge.js`：完整历史与原生接口。
- `Resources/game-review.js`：网站准确度公式、严格变化线验证、中文棋规讲解。
- `Resources/stockfish-review.js`：本地 UCI worker 管线；`Stockfish/`：未修改的 lite 引擎、GPL 许可、上游对应源码归档。
- `Tests/`、`UITests/`、`scripts/engine-tests.cjs`：棋规、搜索与评分、状态竞争、存储、原生 UI 流程。

## 规则与分析边界

棋规覆盖王车易位、吃过路兵、四种升变、将死、逼和、子力不足。本地人机模式把三次重复和五十回合判为自动和棋；这是产品约定。每局最多 600 半回合。

复盘按网站方式分析全部 n+1 个局面，完整历史传给引擎；Skill 20、Hash 32、MultiPV 1，每局面快速 450 ms 或细致 1400 ms。白方为正，将死独立显示；计算准确度时按网站将死/和棋映射处理。逐着公式、五局面波动权重（1–12）、最佳/唯一合法着修正和双方加权/调和平均都与网站一致。测试使用网站代码生成的固定评估样本核对；实际限时搜索会因设备和搜索深度产生不同分数，不能承诺同一 PGN 每次百分比完全相同。没有 Elo 估算。

解释只依据棋规和已展示的变化，吃子与净子力得失分开；一条合法将死线不被描述为已穷尽所有防守。取消/失败不生成部分准确度；重新分析期间标明仍显示上次完整报告。关闭复盘或进入后台终止 worker。

## 本地数据与许可

数据在 App 沙盒 `Library/Application Support/YiwaiPractice/` 下的 `notebook.json` 和 `games-v1.json`。读取失败保留原文件并提示；卸载 App 会删除记录。测试使用独立数据文件。

完整来源见根目录 `NOTICE.md`。原创 App、适配代码和原创资源按 GPL-3.0-or-later 授权；chess.js 保留 BSD-2-Clause，Stockfish 保留其 GPL 许可。上游源码可在关于页导出，完整 App 对应源码由本仓库提供。
