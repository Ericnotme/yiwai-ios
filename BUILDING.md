# 构建 0.3.1（4）

## 原生应用

已验证的环境为 Xcode 26.1、iOS 26.1 模拟器；部署目标为 iOS 17.0。需要 macOS、完整 Xcode、Python 3；Node.js 用于 JavaScript 测试。应用使用随包资源，不依赖 npm、CocoaPods、Swift Package 或远程服务。

```sh
cd YiwaiPractice
python3 scripts/generate-project.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project YiwaiPractice.xcodeproj -scheme YiwaiPractice \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build -jobs 1 build CODE_SIGNING_ALLOWED=NO
node --test scripts/engine-tests.cjs
node --test scripts/review-tests.cjs
node --test scripts/stockfish-transport-tests.cjs
```

模拟器测试可用 `scripts/test.sh`，默认选择 iPhone 16e；若未安装该设备，使用本机已有模拟器替换脚本中的 destination。运行完整 UI 测试需要相应模拟器运行时和足够磁盘空间。

工程默认 `CODE_SIGNING_ALLOWED=NO`，没有写入 Team、证书或描述文件。实机安装时用 Xcode 打开工程，使用自己的唯一 Bundle Identifier 和 Signing & Capabilities 配置。只需常规签名，不需要原开发者密钥。没有隐藏激活、服务口令或安装授权数据。

## 重新编译上游 Stockfish

应用内已携带未修改的 lite single JS/WASM，普通 App 构建无需重编它们。对应上游提交、源归档、许可和精确资源哈希见 `release-manifest.json`。

重新编译需要 Node.js、Python 3、GNU make，以及上游 `build.js` 指定的 **Emscripten 3.1.7**。先按 https://emscripten.org/docs/getting_started/downloads.html 安装并激活该版本，再在当前 shell 中加载 `emsdk_env.sh`。构建辅助脚本不安装工具、不修改全局配置。

在仓库根目录运行：

```sh
sh scripts/rebuild-stockfish.sh
```

脚本校验随附源码和 NNUE 文件的 SHA-256，解包到 `build/stockfish`，复制网络至上游 `src/`，然后运行：

```sh
node build.js --lite --single-threaded --no-split --strict-em-check -f
```

对应输出为解包工程 `bin/stockfish-19-lite-single.js` 和 `.wasm`。完成后可替换应用 `Resources/Stockfish/` 中的同名文件并重新构建 App；修改版须保留许可并发布相应源码及修改说明。

本次源码交付核对了上游 commit、构建脚本、网络名称/哈希和应用归档资源，没有重新执行 Emscripten 构建，**不声称重新编译会逐字节复现 npm 的 WASM**。生成日期、编译器和环境可能改变输出；网络本身的完整哈希已验证。原分发 JS/WASM 和它们对应的上游源归档原样保留。

## 完整性验证

在仓库根目录运行 `python3 scripts/verify-source.py`，校验全部应用编译输入和随附网络。根目录说明和授权是本次源码发布追加的材料，不会声称修改过已归档二进制。
