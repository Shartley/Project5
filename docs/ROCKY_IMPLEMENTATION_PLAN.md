# Project 5: Rocky's implementation plan

Status: desktop slice and Quest adapters implemented. See README and ROCKY_INTEGRATION.md for tested behavior and current limits; native Quest export and physical-headset acceptance remain pending prerequisites/hardware. The sections below retain the original implementation specification.

## 1. Outcome and boundaries

Build a playable first-person slice of **Solo Leveling: Awakening** containing all of Rocky's Player Stats and Practice Mode work, including the workout and Penalty Zone. Support keyboard/mouse and Meta Quest 3/3S with tracked controllers. Use the kickoff's System UI palette and simple low-poly 3D geometry.

The starting repository has an empty main scene, Godot 4.7 configuration, the Compatibility renderer, and the existing Godot MCP integration. Godot 4.7.2 is installed locally. Preserve the existing integration and renderer.

**Successful delivery means:** the user can press F5, play through Rocky's features without teammate code, inspect and change test conditions, run automated checks, and follow documented instructions to test the same features on Quest.

Rickey retains ownership of production combat, enemy AI, and the final player rigs. Samaii retains ownership of production gates, extraction, and passthrough. Supply small, clearly identified stand-ins for those dependencies so Rocky's work runs independently. Production teammates replace these through adapters, without rewriting stats, workout, or practice logic. Full dungeon progression, extraction, production enemy models, and bare-hand tracking are outside this slice.

Source: `Project 5 Kickoff (1).pdf`, especially sections 2.5, 2.6, 3, 5, 6, and 7, including the architecture diagram on page 8. The selected delivery is all Rocky work on desktop and Quest, tested primarily through Godot, with themed UI and simple 3D.

## 2. Shared state and integration contracts

Use typed GDScript and the kickoff's two shared autoloads:

| Component | Owns | Public integration surface |
| --- | --- | --- |
| `PlayerStats` / `player_stats.gd` | Level, XP, rank, five stats, unspent points, HP, MP, Fatigue, potions, and Return stone count | `add_xp`, `spend_point`, `apply_incoming_damage`, `try_spend_mp`, `add_potion`, `use_potion`, `try_add_fatigue`, `set_sprinting`, `set_awake_enemy_count`, `restore_after_death`, and derived-stat getters |
| `Progress` / `progress.gd` | Workout resolution, portal access, cleared gates, unlocked enemy types, stored-shadow type references, and mastered types | `complete_workout`, `resolve_penalty`, `register_gate_clear`, `register_stored_shadow_type`, and idempotent `award_mastery` |
| Persistent main scene | One player rig, HUD, current content scene, pause state, and test tools | Swap hub, training, and penalty content beneath the rig; do not recreate session state on scene changes |
| Combat adapter | Connects combat events to shared state and training | Announce wind-up start, attack ID, enemy type, impact time, and final defense result; request outgoing damage multiplier, parry window, and dash cooldown |
| Input/pose adapter | Desktop input, real OpenXR tracking, or recorded test poses | Emit common workout, potion, defense, and UI intents; expose valid headset/controller poses in tracking space |

- Publish signals for resource/stat/inventory changes, level-ups, player death, progression changes, and mastery rewards. UI observes signals rather than writing state directly.
- Use stable enemy IDs and data Resources. Start with the kickoff's seven enemy definitions; share identity, wind-up, damage, and movement data between practice and stand-ins. Combat adapters own collision/defense resolution; stats apply player mitigation exactly once afterward.
- Gate and extraction code announce clears and stored-shadow types to `Progress`; Rocky does not duplicate their progression logic. Goblin is available initially. Warren clear adds Kobold, Goblin, and Chieftain; Nest clear adds Lizardman, Spitter, and Kasaka. Stored-shadow types join the list without duplicate entries.
- Rank changes are explicit calls from gate progression, not consequences of gaining levels. Return stones start at two and remain available to Samaii's integration; this slice does not implement Return stone travel.
- Keep all progress in memory until exit. Pausing freezes gameplay timers. A new launch or the explicit debug reset creates a fresh session; changing rooms does not.
- Document these contracts alongside the implementation so teammate adapters have one source of truth.

## 3. Required behavior and explicit defaults

### Player Stats

- Start at Level 1, rank E, all five stats at 10, zero unspent points, 100/100 HP, 20/20 MP, and 0 Fatigue. Inventory: three health potions, one mana potion, one tonic, and two Return stones.
- Define the cost to leave level `L` as `round(50 * L^1.6)`. Carry surplus XP through multiple level-ups; each grants five points and fills HP. Cap level at 50, display MAX, and discard XP beyond the cap. Spending requires an available point and cannot be undone.
- Use the stat table's **points above 10** interpretation consistently. For `b = stat - 10`: Strength multiplier `1 + 0.02*b`; max HP `100 + 10*VitalityBonus`; Vitality damage reduction `0.005*VitalityBonus`; max MP `20 + 2*IntelligenceBonus`; dash cooldown `max(1.6, 4*(1 - 0.01*AgilityBonus))`; Fatigue recovery `15*(1 + 0.01*AgilityBonus)` per second.
- Expose Perception's parry window as `0.150 + 0.004*PerceptionBonus` seconds, plus 0.020 against a mastered type. Crit chance is `0.05 + 0.01*PerceptionBonus`, capped at 1. Boss weak-point visibility begins at Perception 15. Expose Intelligence's shadow multiplier `0.75 + 0.02*IntelligenceBonus` and extraction bonus `0.01*IntelligenceBonus`; Samaii applies extraction's 95% ceiling.
- Clamp resource values and reduction percentages to valid ranges. Apply Vitality mitigation and, when already below 30% HP at Level 5+, the additional 50% damage reduction before rounding final incoming damage once. Block/parry/dash resolution happens before this method.
- Full heal means HP only. Level-ups and workout completion do not refill MP or clear Fatigue. Raising Vitality or Intelligence raises the maximum without refilling the current resource.
- Sprint adds 5 Fatigue/second, block adds 10, and dash adds 15. After one second without a Fatigue-producing action, recover at the Agility-adjusted rate. Reaching 100 locks sprint and dash until Fatigue is strictly below 50; block remains available. Spending Fatigue for an accepted action can reach the cap.
- Regenerate MP at 1/second, or 0.3/second while any enemy is awake. Track an awake-enemy count so multiple enemies cannot incorrectly toggle this state.
- Health potion restores up to 50 HP evenly over two seconds; mana restores up to 30 MP immediately; tonic sets Fatigue to zero. Carry caps are 5/3/3. An empty inventory, an already-full target resource, or an active health-potion effect rejects the relevant use without consuming a bottle. Different potion types may overlap. Death cancels pending healing.
- Below 30% HP, show a restrained red edge warning, a readable LOW HP indicator, and a heartbeat. No camera shake or full-screen flashes. Death emits one event, preserves XP, and restores full HP and zero Fatigue through the active scene's respawn handler.

**Kickoff discrepancy resolved for this slice:** section 2.1 uses raw Strength in its damage formula, while section 2.5 describes bonuses above 10. Use the table-based multiplier above, yielding 1.0 at Strength 10, and explicitly flag this choice in Rickey's combat handoff. Keep the calculation centralized.

### Workout and Penalty Zone

- Provide a 6 x 6 m stand-in hub with the central workout pad, portal-lock indicators, pause menu, and access to Training. Workout completion follows 5 squats, 10 punches, 5 squats, 10 punches.
- Desktop shows a countdown/beat prompt every 0.8 seconds. Space counts for squats; either J or K counts for punches. Accept the requested input within +/-0.15 seconds of its beat, once per prompt. Misses repeat the outstanding rep on a later beat. Workout input takes priority over dash bindings.
- Quest calibrates standing headset height, counts a squat only after dropping below 80% and returning above 95% over at least 0.8 seconds, and counts a punch when a controller hits the glowing target at 2.5 m/s or faster. Keyboard beat tolerance does not apply to VR gestures. Rearm after returning/retracting so one motion cannot count repeatedly.
- Detect VR motion in tracking space: locomotion, snap turns, recentering, tracking reacquisition, and scene placement must not become punches or squats. Clear unfinished gesture history after invalid tracking or recentering.
- Completion gives three points, fills HP, and opens the portals exactly once. After completion, or resolution through the Penalty Zone, the workout cannot be restarted in that session.
- Abandon opens a 20 x 20 m Penalty Zone. Start the first Centipede at 15 seconds, then attempt a spawn every 15 seconds, with at most four alive; skip occupied spawn opportunities rather than building a backlog. Survive 180 gameplay seconds to earn 50 XP. Both survival and death return to the hub and open portals; death grants no survival XP, and neither outcome grants the workout's three points.
- Supply a primitive Centipede stand-in that approaches and attacks using its kickoff values, plus enough dagger, block, and dash functionality to make survival playable. This is a test implementation of Rickey's interfaces, not his full combat system. Penalty enemies grant no kill XP or extraction.
- Limit stand-in enemies to two simultaneous attack tokens. The test dagger needs light attacks only: base 10, a 2.2 m desktop reach, and the kickoff's 0.1/0.15/0.2-second attack phases. Block reduces damage by 80%; dash blinks up to 3 m, stops 0.3 m before walls, and grants 0.2 seconds of invulnerability. Resolve dash, parry, block, then damage in that order; use shared stats for costs and cooldowns.

### Practice Mode

- Esc/Menu > Training opens a 10 x 10 m room from the hub; Leave returns to the hub. Choose one or two enemies and wind-up speed 100%, 75%, or 50%. Divide base wind-up duration by the selected speed; do not scale the parry window or global game time.
- Use nonlethal stand-in attackers with clear pose, sound, and warning-symbol cues. Reuse defense events on desktop and XR. The player takes no damage, enemies cannot die, and attacks award no XP or loot. Normal fatigue behavior remains active.
- On desktop, right-mouse press time determines parry eligibility and holding it blocks from the front 120 degrees. In XR, a parry requires the test blade to contact the incoming weapon at 2 m/s or faster inside the shared parry window; an interposed blade blocks. Accept at most one resolved defense result per attack ID. This bridge must be replaceable by Rickey's production combat events.
- Finalize exactly one grade per attack: `[Perfect.]` for a successful parry, `[Too early.]` for a defense attempt before its window without a later successful parry, and `[Too late.]` for no successful attempt before impact. An ordinary timely block is not Perfect. Include boundary tests at the exact window start and impact time.
- Every ten resolved attacks shows Perfect count and parry rate. A round at 100% speed containing one enemy type and at least seven Perfect results masters that type. Two enemies of the same type still qualify; mixed types and slower speeds do not. Changing setup starts a fresh ten-attack round.
- Mastery grants one point and a permanent-within-session +20 ms window against that type, once only. Future practice and normal combat query the same mastery record. Leaving/reentering Training cannot duplicate rewards.

### Desktop, Quest, and presentation

- Keep the player rig loaded while content changes. The test desktop rig supports WASD, mouse look, Shift sprint, and Space dash; normal speeds are 3/5 m/s. The Quest stand-in uses OpenXR head/controller tracking, 1.5/3 m/s stick movement outside the hub, and 45-degree snap turning. Hub stick movement is disabled, matching the kickoff; its test menu makes room transitions accessible without production portals or passthrough.
- Tab opens desktop stats with clickable plus buttons. Keys 1/2/3 use potions. In XR, X opens stats, the left wrist displays resources, and controller tips support poking buttons. Use ray/trigger selection for training configuration. Bottles are selected from the wrist inventory, held with left grip, and consumed once when brought within 0.15 m of the headset's mouth marker; require exit/reselection before another consumption.
- Use core OpenXR and an Oculus Touch action map for this controller-based slice. No XR Tools or bare-hand dependency is required. Add vendor/passthrough integration with Samaii's work when needed.
- Make desktop the F5 default and provide explicit Desktop, XR, and Simulated XR launch profiles. Pass `--xr-mode off` for desktop tests and `--xr-mode on` for real XR. Show actionable failure information and allow desktop fallback if XR initialization fails on PC; do not silently report XR tests as passed.
- Simulated XR replays recorded head/controller poses through the same input adapter. It tests gesture logic and UI intent routing without claiming headset rendering, comfort, or real tracking validation.
- Include a native Quest Android debug export preset and deployment instructions, as well as a PC Quest Link launch path. Prerequisites are matching Godot export templates, OpenJDK 17, Android SDK configuration, and a developer-enabled/authorized headset. Local SDK availability and headset access still need confirmation during implementation. Follow [Godot's Android XR deployment instructions](https://docs.godotengine.org/en/stable/tutorials/xr/deploying_to_android.html); build/deploy success is a required hardware acceptance step.
- Reuse one System theme for screen and world-space UI: Navy #0B1A2E, Blue #3FB8FF, Gold #FFC94A, Red #E5383B, Off-White #DADADA, and Purple #7B3FE4. Use text and symbols alongside color. Begin with the kickoff's 2 m cyan portal as the visual anchor, then build simple matching geometry, original/synthesized cues, and readable panels. No official franchise art or logos.
- The persistent XR rig and startup behavior follow [Godot's XR setup guidance](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html); explicit launch switches follow the [command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

## 4. Implementation order and user test path

Each increment must leave F5 playable before the next begins. The kickoff's November 18 desktop milestone is stats/workout; its December 2 milestone adds penalty, practice, and VR. These dates describe the original targets, not completed work.

1. **Playable foundation and Player Stats.** Add the persistent main scene, the two autoloads, simple hub, desktop test rig, System theme, HUD/status/inventory, pause handling, and test panel. Verify damage, leveling, point spending, resource recovery, and scene persistence.
2. **Workout and penalty.** Complete the desktop workout, one-time rewards, portal-lock state, abandon flow, timed arena, primitive attackers, and return/death handling. Add pose-based workout logic behind the input adapter in the same increment.
3. **Practice and mastery.** Add selection/unlocks, slowed wind-ups, shared defense grading, ten-attack reports, and idempotent mastery rewards. Exercise gate-clear and stored-shadow integration using test events.
4. **Quest parity and deployment.** Connect the real OpenXR rig, wrist/world UI, pokes/rays, bottles, movement, and defense gestures. Finish Simulated XR scenarios, PC Link instructions, Android preset, and on-device checks.
5. **Handoff and verification.** Replace accidental direct dependencies with the documented adapters, run automated checks and both input-mode acceptance passes, and update the README with exact launch/test steps and known hardware limitations.

The completed test experience must be:

- Import `project.godot` in Godot 4.7.2 and press **F5**. Enter the stand-in hub with instructions visible; no headset or MCP connection is required.
- Press **F1** for a debug-only test panel, also reachable from the in-headset pause menu. Expose XP/point grants, damage and resource changes, awake-enemy count, potion inventory, gate/shadow unlock events, round-result inspection, and a complete session reset.
- Provide labeled scenario shortcuts for low HP at Level 5, Fatigue lock/release, practice mastery, and a nearly complete Penalty Zone. Allow time advancement through the simulation clock without editing the production 180-second duration or 15-second spawn interval. Display when a scenario has changed test state.
- Run a documented headless test command. The runner prints failed assertions and exits nonzero on failure; avoid a third-party testing dependency for this slice.
- For headset testing, select the XR launch profile for Link, or deploy the Quest debug preset through Godot's Android device controls. Document controller bindings and the same test scenarios in the README.

## 5. Verification and completion criteria

| Area | Required scenarios |
| --- | --- |
| Progression | Exact starting state; XP at/under/over thresholds; multiple level-ups; cap 50; no spending with zero points; derived values update; data survives content swaps and resets on a fresh session |
| Resources | Damage mitigation applied once; low-HP threshold and Level 5 boundary; MP awake/rest rates; Fatigue reaches 100 and remains locked at 50 but releases below it; rest delay and Agility recovery; death emits once |
| Potions | Empty inventory, carry caps, full-resource rejection, two-second healing, repeat health-use rejection, cross-type use, and cancellation on death |
| Workout | All 30 reps; wrong keys; beat edges, misses, and duplicate inputs; abandonment; no repeated rewards; recorded squat/punch speed/duration boundaries; invalid tracking and recentering |
| Penalty | First spawn at 15 seconds; four-alive cap; replacement spawning after a death; survival at 180 seconds; exactly 50 XP once; no reward on death; both exits open portals; pause does not advance timers |
| Practice | One/two attackers; three speeds; correct window math; all grades; exactly ten grades per report; 6/10 versus 7/10 mastery; mixed/slowed rounds excluded; same-type pair allowed; duplicate mastery rejected; no damage/death/XP/loot |
| Integration | Gate clear and stored-shadow events update the catalog; Perception 15 exposes weak points; mastery window applies to normal defense through the adapter; scene exit clears awake attackers and stale attack/gesture events |
| User experience | F5 works without a headset; pause/status menus release and restore mouse focus; F1 reset restores the entire session; UI is legible and warnings have non-color cues; real/simulated input routes to the same feature logic |
| Quest | Verify actual headset rendering, wrist UI, pointer/poke selection, squats, punches, bottles, practice defense, snap turn, tracking loss, pause/resume, and scene changes on Quest 3 or 3S; verify both Android deployment and Link launch |

Use deterministic, injected time and recorded pose samples for numerical/timing tests. Use live Godot playtests for input routing, collisions, scene flow, visual layout, sound, and XR interaction. When the editor is available, use the existing Godot MCP tools for input/state checks, alongside captured game-process errors.

Target stable 72 FPS on the supported Quest hardware for these simple test scenes. Record actual headset/runtime and measured results; a desktop or simulated-XR pass does not satisfy the hardware criteria. If no headset is available, deliver the desktop/simulation result with the real-device acceptance items explicitly pending.

The final handoff includes source scenes/scripts/resources, debug test controls, automated checks, a Quest debug preset, the teammate API contract, and a README walkthrough. It does not require a Windows standalone executable or store publication.
