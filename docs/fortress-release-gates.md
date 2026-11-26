# Fortress course · release gates

2026-11-26 — candidate **0.4.4 (16)**, existing bundle `chat.weijiaxian.yiwai.practice`, App ID `6821928220`. This is an isolated development candidate, not an Apple upload or release. Public main remains the older 0.4.0 source. The integration preserves the actual local 0.4.3 baseline `aed8347` and continues draft PR #2.

## Product and scope

The original three-prediction prototype was too limited for product acceptance. The candidate now has four selectable chapters and sixteen authored condition questions: bishop color and actual attack lines; blockers, kings and pawn attacks; promotion and protection; and the limits of transferring a rule to changed positions. Every candidate UCI move is checked by the bundled rules engine. Feedback can show the position before and after a legal move; an illegal candidate is never replayed as legal, and a clearly labeled legal alternative is not called a best move.

The course map records answered questions. First answers are immutable; later attempts retain their own answer and time. Each record includes the catalog version and exact question definition, so later revisions cannot silently change the meaning of an earlier answer. “Answered” does not mean “mastered,” and no Elo or learning-transfer benefit is claimed.

The three existing playable wrong-bishop rook-pawn seeds remain directly accessible. Their defensive policy stays restricted to the already verified canonical White a-file case. The course's changed corners, sides and extra pieces do not expand that policy or establish their game-theoretic outcomes. This is a classical endgame lesson, not a solution of the standard initial chess position. CHECKMATE PR #4 remains independently unreviewed.

## Data and provenance

The original production project and the November 15 experimental curriculum-export repair were fully backed up before integration. The original checkout remains untouched. Production game, notebook and other existing study stores are retained. The later experimental curriculum is not silently substituted for the production app.

Build 16 adds a separate `fortress-progress-v1.json` local file. Writes are atomic; unreadable, missing-after-load or incompatible records block overwriting and complete export, with a visible error. TimeCapsule schema 6 adds optional `fortressProgress` and `fortressLessons`; schema 4 snapshots still decode without inventing missing course data. Existing export fields retain their meaning. Demo-space export excludes personal course progress. There is still no whole-capsule import/restore feature.

No new account, analytics, network service, payment or new bundle is introduced. Local and bundled privacy text describe the new course records; the public-main privacy URL must still be synchronized with the approved final source before submission.

## Completed evidence and historical limits

- Live App Store Connect inventory and exact review messages were read in the signed-in account. Formal 0.3.4 (7) is Rejected under 4.3(a) with Extended Review; external TestFlight 0.4.3 (13) is independently rejected under the same concern. “Binary State Validated” is processing status, not approval.
- Apple has not named a comparison app. The account's other chess-related record, 弈合, is Prepare for Submission and TestFlight shows No Builds. No app record was deleted or assumed to be the comparison app.
- With explicit account-holder approval, a clarification was sent in the existing formal review conversation and read back as Messages (2). No Resubmit or new-binary upload was performed.
- The owner’s iPhone started at 0.3.3 (6). App data was backed up before installing development build 14. All 18 saved games were byte-identical after launch and automated Fortress interaction. After owner play, all game IDs and moves still matched; only one update timestamp changed. A fresh backup preserves that later state.
- Owner play of build 14 confirmed independent completion but identified insufficient lesson depth. This is a product gate, not overall acceptance of build 16.
- Build 15 fixed static/tap-only board scrolling at large text sizes while retaining square taps and real dragging. It passed 88 native unit tests, 55 JavaScript tests, unsigned arm64 Release, existing-identity development signing, four focused phone-simulator UI flows and iPad large-text/landscape checks. Its full 33-test local run passed 31; two file-picker location guards failed before saving; after correcting the UI location checks, both focused reruns passed and actual local export files were verified. Those raw results and focused corrections are kept separately, never relabeled as a single green full run.
- Build 16 course data passed all 16 exact-bridge legality checks, including king safety, valid legal-move replay, rejection of illegal candidates and a locally legal one-ply predecessor for each synthetic position. This is not full historical reachability from the initial chess position or a win/draw proof.
- Build 16 passed all 94 native unit tests and 55 JavaScript regressions. The two focused Fortress UI flows passed, including immutable first answers after retry/relaunch, legal evidence, all four promotions, undo, a confirmed second-seed change and restart. Final unsigned arm64 Release and existing-identity development signing passed. The full 34-case UI suite and exact-commit remote CI remain separate gates.
- At the latest phone connection check the device was unavailable. Build 16 is prepared but not yet installed; build 14 and its owner-play data are retained. The owner has been asked to reconnect and unlock the phone.

## Remaining release gates

- [ ] Final build 16 source manifest, full native/unit/UI tests and unsigned Release succeed; inspect all failures and preserve xcresults/logs. A focused rerun is distinguished from a full-suite result.
- [ ] Development sign and install the final candidate with the existing authorized identity after preserving the latest phone data. Verify final-build courses, evidence toggles, persistence, full export, promotions, undo/restart, real offline launch, large text and VoiceOver.
- [ ] Repeat owner acceptance on the expanded course, then observe 5–10 voluntary testers completing the learning loop without coercion. Do not count automation or a developer's interaction as human learning evidence.
- [ ] Clarify and address Apple's actual binary/metadata/concept similarity concern. A larger question count does not itself prove 4.3(a) resolved. Do not create another bundle to bypass review, delete apps, change account identities or accept agreements.
- [ ] Match final privacy/support URLs, complete corresponding source, licenses, metadata, screenshot dimensions, export compliance and supported-device behavior to the exact candidate.
- [ ] Confirm intended platform scope. Current regions are Hong Kong, Macau, Taiwan and the United States; generic notices for other regions do not by themselves establish a current-region blocker. Mac/Vision iOS-app availability is enabled, while compatibility remains unverified. No scope setting was changed.
- [ ] Only after the preceding gates: distribution archive, signing/validation, upload and processing check on the existing app. External beta review and formal App Store review are separate. Recheck the live highest build number immediately before upload; latest observed Apple upload is still 0.4.3 (13).

Original historical run https://github.com/Ericnotme/yiwai-ios/actions/runs/45755023802 was cancelled: 56 unit tests passed, 2 of 23 UI tests failed, Release was skipped. Intermediate runs superseded by later commits are also not green evidence. Current native CI preserves raw logs, source commit and xcresults even on failure.

References: https://developer.apple.com/app-store/review/guidelines/ ; https://github.com/Ericnotme/weijia-open-studio/pull/3 ; https://github.com/Ericnotme/weijia-open-studio/pull/4 .
