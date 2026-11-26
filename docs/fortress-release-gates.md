# Fortress Lab · release candidate / 上架验收

2026-11-26 — candidate on top of the last accessible public source 0.4.0 (10). Not an App Store release, not the newer local Xcode project, and not a signed archive. Do not replace any newer local build with this branch. Main remains unchanged.

## User-facing product
A native proof-driven lesson reachable from the default practice screen, not a web wrapper or another chess bundle. The three condition questions use the bundled legal move engine, not an arbitrary answer table: can Black return to a8; what changes when the bishop moves to the other square color; and why one legal return does not prove the full invariant. Players then attack as White in three synthetic fortress seeds; the defender follows the geometric rule. Four promotion choices, legal-move targets, atomic attack/reply, undo, restart, seed change, proof explanation and boundary are implemented. No account, new analytics, network requirement, payments, or data migration. Session lives only in memory.

## Evidence and gates
- [x] Portable Swift session model and policy compiled locally on Linux.
- [x] Independent restricted geometry fixture generator checked 96 trajectories, 2,217 attack/reply turns, 2,217 undo/replay checks, 93 terminal draws, 285 invalid/atomic rollback checks, 3 quiz answers, and 4 promotions. The other 3 trajectories ended at the fixture horizon, not proven draws. This checks the session against fixtures, not SwiftUI or Apple signing.
- [x] Native source syntax parsed; five new app/test files registered in the existing Xcode project. Training defaults to the practice tab.
- [x] Native XCTest and UI regression source added. GitHub macOS workflow started, see https://github.com/Ericnotme/yiwai-ios/actions/runs/45755023802 . Treat this as pending until its actual completion.
- [ ] Full Xcode Debug simulator tests and unsigned Release build pass on the candidate's exact commit; inspect any failures and screenshots. Candidate includes tests for all first moves from the three seeds, all four promotions, undo, bad move rollback, quiz and native UI interaction.
- [ ] Compare and integrate these changes into the **actual latest local project**, not the older snapshot, preserving the real bundle ID and data. Re-run all regressions on the resulting exact source. Set the next version/build based on App Store Connect's current record, not this draft.
- [ ] Real iPhone verification: enter the lesson, all promotion choices, draw/undo/restart, no network, large text, VoiceOver, no crash, previous games and notes remain intact. Obtain actual screenshots on supported devices, not mockups.
- [ ] Apple account holder verifies exact App Review message, app record, duplicate/similar app records and version. Apple's 4.3(a) addresses multiple Bundle IDs of the same app; 4.3(b) addresses indistinguishable apps. Do not create another app record, change the bundle to evade review, accept terms, delete apps, or submit a binary before resolving the actual concern.
- [ ] Sign/archive/validate and upload using the existing authorized Xcode identity and confirmed app record; verify privacy labels, support/privacy URLs, licenses, screenshots, export compliance, and build processing. External TestFlight install and formal App Store approval are independent gates.
- [ ] Before claiming commercial readiness, observe 5–10 voluntary testers completing the learning loop. Do not promise improved Elo or learning transfer based on simulation.

## Draft App Store listing (not submitted; confirm against the final build)

Name: 弈外 · 国际象棋思考训练 (subject to availability and current app record)
Subtitle: 看懂每一步背后的原因

Description:
弈外是一间中文国际象棋学习室。比起直接背答案，你可以先判断局面，再亲自走棋，改变一个条件，观察原来的结论是否仍然成立。

不败空间：试着攻破一个由数学规则防守的残局。比较错色象与正确色象的不同，尝试不同的升变方式，在亲自攻防后阅读证明及适用边界。挑战来自经典残局，不声称已解决国际象棋初始局面。

棋谱与学习：导入 FEN/PGN、回放走法、比较变化线，复习本机保存的学习记录。现有功能只在最终实际构建包含且经验证时保留此段描述。

学习内容不要求登录，不需要联网调用 AI。现有棋谱和备注保留在设备；外部研究链接只在主动打开时访问。以最终构建的隐私核验为准。

## Reviewer notes (only after actual native validation; not sent)

The app is an educational chess product, not a collection of equivalent chess apps. Start on the Practice tab, open 不败空间, complete the three a7→a8 legal-move predictions, and start the fortress challenge. Move the white pawn a7 to a8 and select any promotion piece. Black follows the stated geometric rule and the bundled rules engine determines the draw. Undo, change seeds, restart, and open the proof explanation. No login, network service, or purchase is required for this flow. The classical endgame lesson is distinct from an engine recommendation; the app does not claim to solve the standard starting position.

If the exact previous 4.3(a) concern has not been clarified, first use the draft clarification from experiments/fortress-lab/README.md and resolve the relevant app-record duplication. Do not claim this feature automatically cures a duplicate-app rejection.

References: https://developer.apple.com/app-store/review/guidelines/ ; https://github.com/Ericnotme/weijia-open-studio/pull/3 ; https://github.com/Ericnotme/weijia-open-studio/pull/4 .
