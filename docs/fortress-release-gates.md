# Fortress Lab · release candidate / 上架验收

2026-11-26 — integration on the preserved production-bundle source `aed8347` (0.4.3, build 13), incorporating Fortress Lab from the earlier PR #2 head `8b83241`. The original local project and the 2026-11-15 curriculum-export repair were fully backed up before work. This is not an App Store release or a signed distribution archive. The integrated candidate is now 0.4.4 (15), following local build 14 and the observed existing Apple upload 0.4.3 (13); upload remains gated on the checks below. This integration is prepared as the continuation of existing draft PR #2. Public main is preserved; this document does not assert that the integrated commit has already been pushed or passed remote CI. See [source reconciliation](fortress-source-reconciliation.md).

## User-facing product
A native proof-driven lesson reachable from the default Learning (学习) screen, not a web wrapper or another chess bundle. The three condition questions use the bundled legal move engine, not an arbitrary answer table: can Black return to a8; what changes when the bishop moves to the other square color; and why one legal return does not prove the full invariant. Players then attack as White in three synthetic fortress seeds; the defender follows the geometric rule. Four promotion choices, legal-move targets, atomic attack/reply, undo, restart, seed change, proof explanation and boundary are implemented. No account, new analytics, network requirement, payments, or data migration. Session lives only in memory.

## Evidence and gates
- [x] Portable Swift session model and policy compiled locally on Linux.
- [x] Independent restricted geometry fixture generator checked 96 trajectories, 2,217 attack/reply turns, 2,217 undo/replay checks, 93 terminal draws, 285 invalid/atomic rollback checks, 3 quiz answers, and 4 promotions. The other 3 trajectories ended at the fixture horizon, not proven draws. This checks the session against fixtures, not SwiftUI or Apple signing.
- [x] Five Fortress app/test files integrated into the actual local 0.4.3 project and registered by its existing project generator. The Learning tab and its personal-PGN, condition-study, export and delayed-review features remain present; the Fortress entry is on that default screen.
- [x] Native XCTest and UI regression source added. The historical public-candidate run https://github.com/Ericnotme/yiwai-ios/actions/runs/45755023802 is **cancelled**, not passing or pending: 56 unit tests passed; 2 of 23 UI tests failed (`LearningPatternUITests` scrolling/hittability and `TimeCapsuleUITests` system file-picker assumptions). The Release step was skipped. Current integrated local validation is recorded separately; a future remote run must use the exact integrated commit and preserve its logs/results.
- [ ] Full Xcode Debug simulator tests and unsigned Release build pass on the candidate's exact commit; inspect any failures and screenshots. Candidate includes tests for all first moves from the three seeds, all four promotions, undo, bad move rollback, quiz and native UI interaction.
- [x] Integrated into the preserved production-bundle 0.4.3 local project, rather than replacing it with the public 0.4.0 snapshot. Persistent stores and export models remain byte-identical to `aed8347`. The later curriculum/bughouse experiments use a different experimental bundle and are backed up, not silently treated as production releases.
- [x] Read the live App Store Connect build inventory and assign the isolated candidate version 0.4.4 (14), above the observed latest upload 0.4.3 (13). Recheck available build numbers immediately before any eventual upload.
- [x] Record the installed physical-device baseline, 0.3.3 (6), and back up its Library/Documents and 18 saved games before a planned upgrade. Backups and personal records are kept outside this repository. A backup is not proof that the new app has preserved data after upgrade.
- [x] Build the 0.4.4 (14) development-signed device candidate using the existing development identity and valid existing profile; strict signature verification passes. This prepares device acceptance testing and does not replace a distribution archive or App Store validation.
- [ ] Complete all regressions on the integrated source, including the entire UI suite and an exact-commit remote run; targeted passes do not close this gate.
- [ ] Real iPhone verification: enter the lesson, all promotion choices, draw/undo/restart, no network, large text, VoiceOver, no crash, previous games and notes remain intact. Obtain actual screenshots on supported devices, not mockups.
- [x] Read the live App Store Connect app identity, build inventory, full formal/Beta review messages and related account records. The observed states are recorded below; reading the messages does not resolve them.
- [ ] Clarify and address the actual 4.3(a) similarity concern. The message concerns a similar binary, metadata and/or concept as apps submitted by other developers, with only minor differences; it does not name a specific competing app. This is broader than a confirmed duplicate-bundle issue in the same account. An Extended Review warning is also present. Do not substitute a generic interpretation of the guideline for the actual message. Do not create another app record, change the bundle to evade review, accept terms, delete apps, or submit before the actual concern and all release gates are addressed.
- [ ] Sign/archive/validate and upload using the existing authorized Xcode identity and confirmed app record; verify privacy labels, support/privacy URLs, licenses, screenshots, export compliance, and build processing. The bundled privacy text and local PRIVACY.md now cover the candidate, but the live online link still targets public main and must be updated to the matching approved source before submission. External TestFlight install and formal App Store approval are independent gates.
- [ ] Before claiming commercial readiness, observe 5–10 voluntary testers completing the learning loop. Do not promise improved Elo or learning transfer based on simulation.

## Local candidate timeline — 2026-11-26

- 0.4.4 (14): initial integrated candidate. Unsigned arm64 Release succeeded; the new iPad Air 11-inch (M3) / iOS 26.1 simulator passed Fortress four promotions/undo/restart, the PGN learning loop and local export, across the original Fortress run and a two-test rerun after adapting the test selectors to iPad tabs. Screenshots and first-run selector failures are retained. These are build 14 observations, not build 15 results. Earlier 88/88 unit tests and 55/55 JavaScript tests also passed before the final metadata/gesture follow-up.
- 0.4.4 (15): distinguish the follow-up from the build 14 already being tried. A maximum-text-size regression exposed a further tap-only-board case: merely checking `enabled` was insufficient because the board still registered a default no-op drag. Drag is now optional and its gesture is enabled only when a real drag handler exists. The stored-data models and bundle remain unchanged. Final unit/UI/build validation is recorded separately; do not relabel build 14 evidence as build 15.

## Build 15 local validation

- 88/88 native unit tests passed, zero failures/skips, on the isolated iPhone 16e / iOS 26.1 simulator. The completed xcresult identifies build 15's source after the final optional-drag / `.subviews` fix. Persistence, corrupt-file protection, legacy decoding, Stockfish and Fortress tests are included.
- Unsigned arm64 iOS Release build succeeded. The built Info.plist reports `chat.weijiaxian.yiwai.practice`, version `0.4.4`, build `15`.
- iPad Air 11-inch (M3) / iOS 26.1 simulator: the targeted maximum-text-size and landscape condition-study UI test passed, with actual screenshots. This is a simulator, not Apple's physical review device. The formal rejection listed the M3 model; the latest beta rejection listed M4.
- 55/55 JavaScript regressions were rerun and passed on the build 15 source; the final test-only assertion follow-up does not change those JavaScript files.
- Development-signed Debug iPhoneOS build 15 succeeded using the same existing certificate and provisioning profile as build 14; strict signature validation passed and the application inputs did not change during signing. No profile was added, no account/signing identity was changed, and this preparation did not install or upload the app. It is a local acceptance package, not an App Store distribution archive.
- Full build 15 iPhone UI regression and exact-commit remote CI have separate results; a preceding run, a stopped run or a successful unsigned build is not substituted for them.

## Live account observations — 2026-11-26

The authenticated App Store Connect account identifies the existing app as App ID `6821928220`, bundle `chat.weijiaxian.yiwai.practice`. Formal App Review and external TestFlight beta review are separate:

| Flow | Actual observed build | Status and evidence |
|---|---|---|
| Formal App Store review | 0.3.4 (7) | Rejected October 22; Guideline 4.3(a), similarity in binary, metadata and/or concept to apps submitted by other developers, with minor differences. Extended Review warning also present. |
| TestFlight beta review | 0.4.3 (13) | Rejected; submitted October 25, review date October 26, Apple message October 27 06:40. Review device listed as iPad Air 11-inch (M4). Same 4.3(a) similarity concern and Extended Review warning. |
| Latest uploaded binary | 0.4.3 (13), October 25 14:33 | Binary State `Validated` describes binary processing, not acceptance by either review process. |

The account's All Statuses inventory contains five app records. The other chess-related record, 弈合 (`com.weijia-lab.yihe`), is 1.0 Prepare for Submission with no selected build, description or screenshots; its TestFlight page says No Builds. Neither rejection identifies it as the comparison app. The account holder separately confirms no purchased template or same-source submission through another developer account; that is an owner statement, not something repository inspection alone can prove. No app record has been deleted or changed in this investigation.

Account availability currently lists Hong Kong, Macau, Taiwan and the United States, not mainland China or the EU. Generic missing-information notices for other regions are not evidence of a block in these four enabled regions. iOS-app availability on Mac and Vision is enabled in the account, while Mac compatibility is not verified; those compatibility claims still require appropriate validation before release. This task changes none of these settings. The physical-device baseline observed is older 0.3.3 (6), with 18 games backed up; it is not an installed 0.4.3 candidate.

Dates and times above are as displayed in App Store Connect; no unverified timezone conversion is asserted. No specific competing app is named. The rejected build must not be relabeled as an approved beta. The rejected 0.4.3 (13) identifier will not be reused. This isolated source is now version 0.4.4 (15). This is a local version/build choice only; no App Store Connect app configuration or uploaded binary has changed. A clarification message was sent in the existing formal review conversation with the account holder's explicit approval; the rejection remains unresolved. A new live build-number check remains required immediately before an eventual upload.

## Draft App Store listing (not submitted; confirm against the final build)

Name: 弈外 · 国际象棋思考训练 (subject to availability and current app record)
Subtitle: 看懂每一步背后的原因

Description:
弈外是一间中文国际象棋学习室。比起直接背答案，你可以先判断局面，再亲自走棋，改变一个条件，观察原来的结论是否仍然成立。

不败空间：试着攻破一个由数学规则防守的残局。比较错色象与正确色象的不同，尝试不同的升变方式，在亲自攻防后阅读证明及适用边界。挑战来自经典残局，不声称已解决国际象棋初始局面。

棋谱与学习：导入 FEN/PGN、回放走法、比较变化线，复习本机保存的学习记录。现有功能只在最终实际构建包含且经验证时保留此段描述。

学习内容不要求登录，不需要联网调用 AI。现有棋谱和备注保留在设备；外部研究链接只在主动打开时访问。以最终构建的隐私核验为准。

## Reviewer notes (only after actual native validation; not sent)

The app is an educational chess product, not a collection of equivalent chess apps. Start on the Learning (学习) tab, open 不败空间, complete the three a7→a8 legal-move predictions, and start the fortress challenge. Move the white pawn a7 to a8 and select any promotion piece. Black follows the stated geometric rule and the bundled rules engine determines the draw. Undo, change seeds, restart, and open the proof explanation. No login, network service, or purchase is required for this flow. The classical endgame lesson is distinct from an engine recommendation; the app does not claim to solve the standard starting position.

The exact previous 4.3(a) concern has not been clarified. Any clarification must describe both review processes accurately and request the specific similar elements or relevant app records. The earlier draft in experiments/fortress-lab/README.md must be checked against these live observations before use. Do not claim this feature automatically resolves the similarity rejection or assert unconfirmed duplicate records.

References: https://developer.apple.com/app-store/review/guidelines/ ; https://github.com/Ericnotme/weijia-open-studio/pull/3 ; https://github.com/Ericnotme/weijia-open-studio/pull/4 .
