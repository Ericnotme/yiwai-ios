# Local source reconciliation — 2026-11-26

This integration starts at the actual local production-bundle source `aed8347` (`feature/personal-pgn-evidence-20261024`), version 0.4.3 (13), bundle `chat.weijiaxian.yiwai.practice`. Its working tree was clean. Neither an older public snapshot nor a newer modification timestamp establishes the latest production release.

## Preserved branches and experiments

- The earlier draft PR #2 candidate (`8b83241`) is based on public 0.4.0. Its self-contained Fortress policy, session, SwiftUI view, native/unit UI tests, validation fixtures and workflow are integrated here. Its old stores, root navigation and version settings are not copied over the newer source. This integrated candidate is prepared to continue that existing draft PR; public main is preserved. A future push and exact-commit CI result must be verified separately, not inferred from this document.
- Local production source `aed8347` adds the interactive learning demonstration, 12-condition study with 4 delayed probes, personal PGN evidence, retrospective notes and expanded local exports. All these features and tests are retained.
- Principle curriculum `28af403` and Bughouse `fd1eb71` are later experiments using `chat.weijiaxian.yiwai.principlelab`. They are not evidence of a newer production-bundle upload and are not imported merely to increase feature count.
- The November 15 repair is a separate, non-Git copy based on `fd1eb71`. Six Swift files add curriculum export in TimeCapsule schema 5, preserve schema 4 decoding, and refuse misleading exports when persisted curriculum is unreadable. The full copy and patch are backed up. This repair depends on the experimental curriculum model, absent from production 0.4.3. It must accompany any future integration of that curriculum; it is not mechanically applied to this unrelated Fortress lesson.
- The November 21 One Square prototypes return to 0.3.4 (7), with local temporary build overrides. Their own handoff warns that later 0.4.x functionality is absent. They cannot replace the latest production source.

## Data preservation

Fortress sessions live only in memory. No new persistent file, migration, reset or deletion is introduced. `GameModels`, `Notebook`, `DecisionReforge`, `PersonalStudy`, `PersonalEvidence`, `ConditionStudy` and `TimeCapsule` implementations remain identical to `aed8347`. Existing Application Support files remain `YiwaiPractice/games-v1.json`, `notebook.json`, `decisions-v1.json`, `conditions-v1.json` and `personal-evidence.json`. Personal notes, raw imported PGN, saved analyses, answers, exposures, delayed-review dates and retrospective notes are retained by keeping the latest models.

The older PR would lose access to later study features and its older archive models omit later data fields. Therefore this work is a selective feature integration, not a checkout replacement. The actual iPhone baseline is 0.3.3 (6), with 18 games; its Library/Documents were backed up before any planned upgrade. Those private backup files remain outside this repository. Automated persistence tests and a successful backup do not establish that the installed app's data survive upgrade; that remains a separate device acceptance check. Source reconciliation itself does not overwrite existing simulator or iPhone data.

## Build identity and manifests

After the completed live-account inventory confirmed latest upload 0.4.3 (13), this isolated candidate was assigned 0.4.4 (14). Only the existing project-generator version constants and generated build settings changed for that version increment; no account record, signing identity or uploaded build changed. It remains gated from upload until validation and review prerequisites are complete. A development-signed device build was prepared using the existing identity and profile, with command-only signing overrides and strict signature verification; no new signing material or distribution archive was created. The previous local README/BUILDING/manifest had stale 0.4.2 (12) labels; the manifest now describes this candidate's exact source inputs without claiming a distribution archive or upload. New source verification covers the newly added files as well as existing application inputs. Agreements and account identities are unchanged.

## Gate status

Current automated results and remaining release gates are maintained in `fortress-release-gates.md`. App identity and review inventory, the next local version/build, and the physical-device backup are established. The entire UI suite, device acceptance, voluntary human learning observations and the specific Apple 4.3(a) concern remain open. An unsigned build or development signature does not establish Apple approval, true offline operation, VoiceOver usability, human comprehension, commercial viability or data preservation after a physical-device upgrade. TestFlight beta review and formal App Review are independent.

Build 15 follow-up: the already-tried build 14 is preserved with its evidence. Build 15 fixes a tap-only chessboard capturing vertical scroll at maximum text size; drag is optional, while `.subviews` preserves square button taps. The follow-up also adapts UI test tab selection to iPadOS. The data models are unchanged. Validation of build 14 does not establish validation of build 15.
