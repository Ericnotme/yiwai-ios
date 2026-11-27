# Personal PGN evidence prototype — 0.4.3 (13), pending TestFlight delivery

Baseline f291479 (0.4.2/12) is preserved at backup/pre-personal-pgn-20261024 and in the existing signed archive/export. Work branch: feature/personal-pgn-evidence-20261024. Roll back by returning to that baseline; do not replace any 0.4.2 artifact.

Scope: one standard-start chess PGN mainline, at most 200,000 UTF-8 bytes and 200 plies, user-confirmed side. Variations/comments remain in the original text, mainline only is analyzed. Nonstandard start/FEN and variants remain available in the old importer but are refused by this evidence pipeline because history cannot be proved. No upload, new account, notification or tracking.

Persist separately: original game/played move; exhaustive rule scan; engine probes (full legal history, typed score and white score perspective, full PV, settings, budget, nodes, depth, duration and stopping reason); qualified branch pair; tentative tactical hypothesis; retrospective first answer and optional reason; feedback exposure; matched practice; delayed retest. Imported game facts never become user explanations. Source and versions travel in the local capsule.

Algorithm: scan every supported ply for missed mate in one. Consider at most three candidate misses, with explicit rejection records. For each, enumerate legal alternatives to the immediately preceding opponent move from the same standard-start history. Require an original mating move to remain legal while the alternate branch has no mate in one. This changes a legal move, not exactly one causal variable; no psychological inference. Verify candidates with Stockfish at 450ms then 1400ms, plus complete independent chess.js legal-move enumeration. Fail closed if unstable/missing. At most one qualified pair per game. No match is an honest completed negative result.

Review pair is retrospective, never an unseen test. Hide answers and evidence until the pair ends. Training uses a clearly sourced, independently validated catalog match, not a claimed personal counterfactual. Retest is available 24 hours after actual practice completion; exclude locally seen/near-duplicate/symmetry-equivalent positions. Finite catalog may be exhausted. Optional statements are not attention measurements; one correct answer is not mastery.

Acceptance: import bounds/variant/FEN/multiple game rejection; legal replay including castle/EP/promotion; all mate answers vs stalemate; engine stability and typed scores; first-answer immutability; crash/pause/cancel/resume; hint/exposure and retrospective exclusions; catalog exhaustion; due time injected in tests; full capsule and old schema; offline iPhone/iPad UI and old regression. No efficacy claim. Source version stays unreleased until build availability is checked and final tests pass. Do not replace 0.4.0 Beta review or accept Apple agreements.

## Review path and evidence interpretation

1. Learning → “体验一局 / 导入我的 PGN” → “体验一局 · 实际本地分析”. This is an explicitly constructed complete standard-start PGN, analyzed by the bundled Stockfish in real time. No private game or login required.
2. Answer the two boards (move squares or choose no mate). Optional candidate/reason may be skipped. Leaving and reopening keeps order/draft/first answer. No answers, hypothesis or PV until both submissions or explicit end. These are retrospective original/related positions, not unseen mastery evidence.
3. Read the actual game move, all mate-in-one answers, legal alternate preceding move, and all legal defences to the nominated critical move. A branch changes multiple relations; it does not establish psychological cause. The user can correct the hypothesis and append clearly marked after-feedback recollection.
4. Begin one matched catalog practice. It is explicitly catalog matching, not a fabricated personal counterfactual. After actual completion, wait 24 hours for two locally unseen, non-near-duplicate matched retest boards (one mate, one no mate). The demo alone can explicitly simulate arrival at due time; that flag is exported and excluded from personal performance.
5. Learning → Time capsule exports schema 4. An unfinished personal round blocks complete export unless explicitly ended because the file contains answers. Raw PGN, engine runs, proofs, full first-answer records, reasons, correction, exposure, due time and source/version remain separate.

Input negative-path example: `1. e4 e5 2. Nf3 Nc6 *`. Confirm white; result must be “已分析，但暂无可靠个人原因题”, without a generic practice advertised as personal generation. Variant/FEN/multiple-game/illegal/201-ply input must be rejected without partial records.

Original 0.4.2 conditions remain 3 families × 4 conditions plus 4 transfer positions. This feature reuses those transparently as a finite matching catalog; it does not add 16 new curated problems or broaden into arbitrary weaknesses. Each qualifying imported game can add one rule- and engine-verified legal branch pair. The original PGN's licensing stays with its provider; private imported content is not published.

Tests use synthetic positive examples for white and black. Fischer–Spassky 1972 round 6 (existing PGN Mentor fixture) verifies real-PGN import and honest negative analysis, not positive personal diagnosis or learning transfer. All delayed tests use an injected or explicitly simulated clock. No real-user efficacy experiment, retention measurement, Elo improvement, or psychological causality is demonstrated.

Release separation: the preserved signed 0.4.2 (12) archive is source f291479 and does not include this branch's new personal PGN feature. 0.4.3 (13) is reserved locally; Apple validation must confirm acceptance before upload is treated as successful. The old 0.4.2 package is retained for rollback and will not be uploaded separately. A local simulator build/source archive is review material, not an externally installable TestFlight build.

Before the first answer, generation progress does not reveal the candidate move number, replacement move, rule scan facts, or rejected candidate details. Evidence appears only after explicit round completion, or an honest completed negative analysis.

## Decision / reason / alternative scope acceptance

The existing prototype meets the requested interaction: the player commits an immutable first choice with optional present-tense reasoning; the original recorded move remains separate; feedback then exposes a replayable legal alternative and objective engine/rule evidence; corrections and later recollections remain distinct. Practice and delayed locally unseen retest complete the loop. This is a chess learning interaction, with no claim to infer hidden psychological causes. No additional product surface is needed for this acceptance.
