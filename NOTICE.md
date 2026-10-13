# 来源、授权及修改说明

## 原创部分

Copyright (C) 2026 Yiwai contributors.

项目权利人授权本版原创 SwiftUI 应用、Seed 引擎、JavaScript 桥接、Stockfish UCI 适配、准确度实现、中文教练、测试、教学内容、图标及构建辅助材料采用 GNU General Public License version 3，或由使用者选择任何更新版本。完整条款见 LICENSE；无担保。

原创范围为本仓库中未在下文列为第三方的文件。源码公开覆盖本版实际编译输入，不包含无关网站服务或其他私人项目。教学局面为原创研究，测试棋谱为人工固定样本。布局参考 Lichess 的官方手机截图；未复制 Lichess 源码、棋子、图标或其他素材。

## chess.js 1.4.0

上游：https://github.com/jhlywa/chess.js/tree/v1.4.0

版权和 BSD-2-Clause 全文保存在 `YiwaiPractice/Resources/chess-LICENSE.txt`。`chess-original.mjs` 是收到的 ESM 原件；`chess.js` 添加许可定位注释、删除唯一 ESM export 行及 source-map 注释以适配 JavaScriptCore，没有修改棋规。`chess-bridge.js` 是本项目的独立适配。

BSD 的版权、条件和免责声明全部保留；这与本项目 GPLv3 分发的要求可以同时履行，第三方文件不被声称为原创。

## Stockfish.js 19.0.0

上游：https://github.com/nmrugg/stockfish.js

精确来源提交：`54fde71d90c7c403964f6cacef48f7bbec495df1`。

本版只使用 `stockfish-19-lite-single.js` 和 `stockfish-19-lite-single.wasm`，从既有弈外网站使用的 npm `stockfish@19.0.0` 资源复制，**没有改动上游 JS/WASM 或引擎源码**。作者、GPL 条款、COPYING、AUTHORS 和构建脚本保留在 `Resources/Stockfish/stockfish19-source.tar.gz` 及 `stockfish19-LICENSE.txt`。源码标头授权 GPL v3 或更新版本；npm 包的标识为 GPL-3.0。

Swift 的 WebKit 容器及 `stockfish-review.js` 使用 UCI 文本与引擎通信；`game-review.js` 实现准确度和证据解释。这些适配均包含在本仓库并按上面的 GPLv3 或更新版本授权。

随应用保留的 `stockfish19-provenance.txt` 是历史网站来源记录，其中的 full WASM 分片和 `/api/engine-full.wasm` 描述只适用于网站，**本 iOS 应用没有携带 full 引擎，也不请求该 API**。保留该文件以便本仓库资源与 0.3.0（3）已归档资源一致；本说明澄清实际使用范围。

## NNUE 网络

Lite 网络：`nn-61e7af4bb97d.nnue`，由上游 `src/evaluate.h` 指定。上游引擎头注明网络作者 Chris Bao (sscg13)。本仓库额外提供该网络文件以支持重新编译；完整 SHA-256 见 release-manifest.json。

官方来源：https://tests.stockfishchess.org/api/nn/nn-61e7af4bb97d.nnue

Stockfish 官方网络仓库说明网络由作者以 CC0 发布：https://github.com/official-stockfish/networks 。对应说明与 CC0 全文保存在 `vendor/stockfish/NNUE-upstream-README.md`、`NNUE-LICENSE.txt`。该网络是引擎构建输入，不是私人棋局数据。

## 上游源归档中的构建工具与示例

原样保存的上游源归档还附带 UglifyJS 3.17.4（BSD-2-Clause）及 `examples/`。UglifyJS 的完整原许可补充在 `vendor/stockfish/UglifyJS-LICENSE.txt`；它仅用于上游构建，不作为 App 引擎执行。

上游 `examples/README.md` 将示例代码标为 MIT。示例附带 Bootstrap 3.0.2（Apache-2.0，Copyright 2013 Twitter, Inc.）、normalize.css 2.1.3（MIT，Nicolas Gallagher 与 Jonathan Neal）、jQuery 1.10.1（MIT，Copyright 2013 jQuery Foundation and other contributors）、chessboard.js 0.3.0（MIT，Copyright 2013 Chris Oakman）及旧 chess.js（BSD，Copyright 2013 Jeff Hlywa）。原标头不变，补充许可全文均在 `vendor/stockfish/`；它们不是 iOS 界面或运行时依赖。

`examples/img/chesspieces/wikipedia/` 为上游示例随附、未由本项目修改的 Cburnett Wikipedia 棋子 PNG。原作者提供 GPL v2 或更新版本等多重许可，本源码集合使用 GPLv3 选项；许可全文见 LICENSE，来源与作者页：https://commons.wikimedia.org/wiki/File:Chess_klt45.svg 、https://commons.wikimedia.org/wiki/User:Cburnett 。本 App 实际棋盘使用系统 Unicode 棋子，不显示这些示例素材。

这些独立第三方材料保留原许可，不适用本项目对原创文件的版权声明。没有将示例库称作修改后的 Stockfish 引擎。

## 对应源码与分发

完整源码及网络在本仓库同版本清单下提供；接收者可复制、修改并按各自许可重新分发。应用本身不要求开发者的账号、私钥或服务密钥才能编译、修改或运行分析。iOS 实机安装使用接收者自己的常规 Apple 签名环境，见 BUILDING.md。Apple SDK、SwiftUI、JavaScriptCore、WebKit 由系统/Xcode 提供，不包含在仓库。

未来提供 TestFlight 构建时，测试说明应包含该构建对应的不可变源码提交链接。该源码发布本身不表示 Apple 已审核或批准该构建。
