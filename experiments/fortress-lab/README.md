# Fortress Lab / 不败空间 — portable core candidate

2026-11-26. Part of the existing YiWai product, not a separate app or bundle ID.

## What is implemented and tested

Foundation-only Swift policy for the canonical a-file corner shelter. Three synthetic starting FENs; after the player makes a legal move, ask the existing chess rules engine for the resulting frame and all legal UCI replies. Pass the FEN and replies into FortressPolicy.reply. Only execute a returned move through the same legal move engine. Stop and report an error for unsupported or inconsistent input; never silently substitute heuristic play. For terminalOrNoLegalMove, use the existing engine's actual terminal classification. If the engine already reports a draw, stop before requesting a reply. The caller owns history and validates that a promotion state is an immediate legal successor. No account, network, new tracking, storage changes, or external play.

Locally compiled with Swift 6.2.1 on Linux. Actual result:
```
PASS: 48243 reply fixtures, 6928 promotions, 217 no-legal-move cases, 5 negative guards
```
41,315 regular black-turn fixtures use complete reply lists from the reviewed V2 Python generator; 6,928 promotion fixtures pass the certified capture as a singleton, not a complete reply list. This tests policy selection, not full native move generation or iOS UI. The Git blob hashes of all three uploaded sources were checked against local sources.

Reproduce from this directory (Python standard library and Swift compiler):
```sh
swiftc -O FortressPolicy.swift main.swift -o /tmp/yiwai-fortress-test
set -o pipefail
python3 generate_fixtures.py /path/to/reviewed/verify_corner.py | /tmp/yiwai-fortress-test
```
Review the Python generator before executing. Its reference source is in [CHECKMATE V2 PR #3](https://github.com/Ericnotme/weijia-open-studio/pull/3) at project-checkmate/submissions/Ericnotme/SC-007/corner-shelter-v2/verify_corner.py. The separate [V3 PR #4](https://github.com/Ericnotme/weijia-open-studio/pull/4) reproduces the V2 counts in C++ and explores predecessor expansion. Classical wrong-color bishop/rook-pawn endgame; neither proves the full chess initial position.

## Release-blocker evidence

Public main at 28da97a4094897a1a736eade4ea9bdfedb961075 corresponds to 0.4.0 (10), and no newer source is available on that branch. Historical project records indicate later build/review attempts, not verified in App Store Connect in this session. Do not overwrite a newer local Xcode project with this older snapshot. The old public TestFlight URL resolves to a page named 弈外练习 with an older source link to yiwai-ios; an invitation page does not prove the current build number, entitlement to install, or formal App Store availability.

Apple current guidelines: https://developer.apple.com/app-store/review/guidelines/ . 4.3(a) specifically addresses multiple bundle IDs of the same app; 4.3(b) covers indistinguishable apps. Obtain the actual reviewer message and exact target app/bundle/version before deciding whether to consolidate, clarify, or resubmit. Do not create a new bundle to bypass review. Keep the feature in the existing intended YiWai app, and distinguish any other chess products by actual functionality or consolidate if they are duplicative. Do not delete app records or alter accounts, agreements or signing without authorization.

## Next acceptance gates

1. Retrieve the latest actual Xcode source and the exact rejection message, current version/build and Apple review status for the intended app. Reconcile with public main.
2. Integrate FortressPolicy as a separate feature into the actual latest code; reuse ChessEngine.frames, GameBoard, legal promotions and terminal handling. Include a clear mathematical proof, challenge seeds, undo and restart. All UI operations remain local. Distinguish a proven policy from a search score. The default training workflow should foreground learning, not a generic engine.
3. Validate in Xcode and on real iPhone: all promotions, capture of pawn/bishop, stalemate, wrong-color boundary, no legal move, undo, app restart, offline mode, large accessibility text. Run existing regression suite and protect saved records. Build with the existing app identity and confirm the signed candidate matches verified source. No claim of an iOS build or signed IPA from the Linux core test.
4. Reply in App Review to ask about the specific duplicate/similarity issue and describe only features actually present in the submitted build. Provide reviewer steps/screenshots and, if necessary, a short screen recording. Submit after exact rejection issues are addressed, not simply on the basis of this PR. Confirm external install separately from App Store approval.
5. After an installable version is confirmed, invite a small voluntary beta cohort (target 5–10) and ask whether they can finish the learning loop and explain the invariant; no incentivized positive ratings or fabricated learning outcomes.

## Draft reviewer clarification (not sent)

Hello App Review team, thank you for reviewing YiWai. We would like to address the specific concern rather than resubmit the same build. Could you clarify which app record, bundle ID, or similarity you identified under Guideline 4.3(a), and whether the issue concerns duplication within our account or another aspect of the submission? Our intention is to maintain one coherent product for chess learning, not multiple variants of the same app. We will use your clarification to resolve any duplication and provide a clear walkthrough of the implemented learning workflow in our next candidate. Thank you.

Status: isolated portable core prototype, **not integrated into the native app target, not signed, not uploaded, not reviewed**. No public app metadata or main branch changes.
