# 本地时间胶囊原型

本原型从 0.3.6(9) 的 FEN/PGN 实现继续；0.4.0 增加的本地学习闭环见 [learning-loop.md](learning-loop.md)，发布状态以本轮交付证据为准。已上传的 build 9 不包含此功能。使用原 App 的「棋谱」入口，无新账号、SDK 或服务。

## 使用

1. 棋谱 → 导入 FEN / PGN → 选择 PGN → 粘贴或选择单盘 UTF-8 PGN 文件 → 导入并打开。
2. 在复盘上方点击「添加个人备注」，编辑后点保存。取消不会写入。备注最多 10,000 字。
3. 棋谱 → 时间胶囊 → 导出本地时间胶囊。保存为 JSON；只要本机副本时，选择系统文件选择器里的「我的 iPhone」。

新导入 PGN 原文本逐字保留，包括换行、注释和变例；棋盘回放沿用原来的主线解析。旧版未保存过的 PGN 注释/变例不能补回。单盘上限仍为 200 KB、600 半回合。不连接或自动抓取 Lichess、Chess.com、Decode，不接受第三方账号凭据，不承诺未知 quiz 格式兼容。

## 文件格式 v2

UTF-8 JSON，`format = yiwai-local-time-capsule`、`schemaVersion = 2`。所有日期用 Unix 秒数。`appVersion` 标明本地原型；`exportedAt` 是快照时间。

- `games`：完整 GameRecord，含 UUID、创建/更新时间、initialFEN、moves、human、level、ending、source、importedHeaders、originalPGN、personalNote、analyses、reviewReport。可选字段为 nil 时不写入。
- `gamePGN`：每条 `recordID` 对应标准 `mainlinePGN`。独立 FEN 和尚未落子的棋局也附有起始局面头，便于重新导入。导入原文在 `games[].originalPGN`。
- `notebook`：全部错题本条目，包括次数、上次练习时间、掌握标记和原有备注。
- `lessons`：完整内置题目定义，避免仅留题目 ID 而失去上下文。
- `decisions`：决策回炉独立版本归档，含用户原话、原局面、记录时机、标签修订、题目完整快照与许可、展示历史、首次答案、提示和完成时间、到期计划与独立通过次数。详见 [决策回炉](decision-reforge.md)。早期 schema 1 导出没有此字段；不补造历史数据。
- `readme`：离开 App 仍能阅读的格式与限制说明。

完整范围是当前能够读取的本机棋谱和错题本记录；不包含系统凭据、临时缓存、未保存的编辑草稿、其他设备或第三方网站内容。损坏的存储文件会保留并阻止误导性的「完整导出」。本版没有整包恢复入口；单盘主线 PGN 可以沿原入口重新导入。以后实现恢复时必须按版本校验、先预览、冲突不覆盖，并另做验收。

## 存储与回滚

继续使用 Application Support/YiwaiPractice/games-v1.json 和 notebook.json，决策回炉单独保存在 decisions-v1.json。originalPGN 与 personalNote 是可选字段，无自动迁移；仅手动导入或保存备注时写入。新增写入先原子保存，再更新可见记录，失败可重试。导出生成独立快照，不改写原文件。

源代码回滚点：813c3c2096c1889786d9df91c2560023fa1043e0（backup/pre-capsule-20261021）。旧版本可忽略新增字段读取，但旧版再次保存会丢失它不认识的字段；实际使用原型后先导出并备份数据再回退。自动化使用 ui-test-* 文件和随机临时目录，避免改写真实棋谱。

本文件及 App 内隐私文本均是本地改动。没有启用云备份、增加数据上传、持续权限、订阅或追踪；导出文件未加密，由用户选择保存位置。用户若选择 iCloud 或其他文件提供者，同步由相应系统服务控制。没有长期或 60 年保存承诺。

0.4.0 新增可选 `decisions.scans`，保存执棋方、棋谱指纹、检测版本、规则证据；`decisions.notes[].evidence` 连接被选中的证据；session.kind 区分 practice/new/original。旧记录不补造扫描或理由。
