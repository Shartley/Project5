# Rocky's integration handoff

Implemented in Godot 4.7.2 with the Compatibility renderer. The shared mechanics are independent of the primitive player/enemy/world stand-ins. Progress is session-only.

## PlayerStats autoload

| Call | Contract |
| --- | --- |
| `add_xp(amount: int)` | Positive XP; carries overflow, cap 50, +5 points and HP heal each level |
| `grant_points(amount: int)` / `spend_point(stat: String) -> bool` | Stat names: Strength, Vitality, Agility, Perception, Intelligence; spending is atomic |
| `apply_incoming_damage(amount: float) -> int` | Pass damage after dash/parry/block and armor resolution; applies Vitality and Level 5 low-HP mitigation once, then rounds; emits `died` once |
| `try_spend_mp(amount: float) -> bool` | Atomic deduction; no negative amounts |
| `try_add_fatigue(amount: float, gated := false) -> bool` | Set `gated=true` for dash; block still works when exhausted |
| `set_sprinting(value: bool)` | Call before each `advance`; exhausted/dead players cannot sprint |
| `set_awake_enemy_count(count: int)` | Feed the combined active-enemy count, not a per-enemy boolean |
| `add_potion(kind: String, amount := 1) -> int` | Returns accepted count; kinds health/mana/tonic; caps 5/3/3 |
| `use_potion(kind: String) -> bool` | Rejects empty/full-target uses and overlapping health effects without consuming inventory |
| `set_rank(value: String)` | E/D/C; gate progression controls rank |
| `full_heal()` / `restore_after_death()` | Full heal restores HP only; respawn also clears Fatigue, death flag, sprint, and potion healing |
| `advance(delta: float)` | Call once per unpaused gameplay tick for MP, Fatigue, and healing; main currently owns this clock |

UI observes `changed`, `notice(message)`, `leveled_up(level)`, and `died`. Do not mutate resource values from production UI. Direct writes in `debug_command` exist only for labeled test scenarios.

Derived getters: `max_hp()`, `max_mp()`, `damage_multiplier()`, `dash_cooldown()`, `fatigue_recovery()`, `parry_window(mastered := false)`, `crit_chance()`, `weak_points_visible()`, `shadow_multiplier()`, `extraction_bonus()`, and `xp_cost()`.

**Formula decision:** use `1 + 0.02 * (Strength - 10)`, matching the stat table. The kickoff combat formula used raw Strength. Rickey should consume the getter so the team has one calculation to adjust if that interpretation changes. A mastered enemy's window is obtained with `PlayerStats.parry_window(Progress.is_mastered(enemy_id))`. Samaii applies extraction's final 95% ceiling.

## Progress autoload

- `start_workout()`, `complete_workout()`, `abandon_workout()`, and `resolve_penalty(survived)` implement the one-time workout/penalty state machine. They return false for repeated or invalid transitions.
- `register_gate_clear("warren" | "nest")` adds enemy types and advances rank idempotently. `register_stored_shadow_type(enemy_id)` exposes eligible stored types in training. These are the two integration calls Samaii needs.
- `award_mastery(enemy_id)` grants one point once; `is_mastered(enemy_id)` provides the combat bonus. Emit mastery only from a qualifying ten-attack practice round.
- Signals: `changed` and `reward(message)`. `reset()` clears progress only; the explicit new-session action also calls `PlayerStats.reset()` and stops transient models.
- Stable enemy IDs: `kobold`, `goblin`, `chieftain`, `lizardman`, `spitter`, `kasaka`, `centipede`. Resource values are in `resources/enemies/`. Centipedes cannot be extracted or normally selected for training.

## Input, combat, and scene adapters

`main.gd` keeps one rig and HUD while replacing `Content`. `change_room` clears transient enemies, awake counts, and gesture history without resetting stats/progress. A production scene manager can call the same models and autoloads while replacing these three test rooms.

Combat currently has a small boundary in `record_defense_attempt`, `resolve_attack`, `hit_enemy`, and `start_training`. Every enemy attack carries a unique ID, type, wind-up start/impact times, and defense-attempt timestamps. Resolve defense in dash > parry > block > damage order. Only the final outcome is handed to the `Practice` model; `record(attack_id, grade)` rejects duplicate results. `configure(types, speed)` resets a practice round. Wind-up duration is base duration divided by selected speed; parry windows are not slowed.

To connect Rickey's combat, replace the test actor events feeding these methods. Do not deduct HP in both combat and stats, award XP inside both enemy and gate code, or add a second per-frame `PlayerStats.advance` call. Production combat must query the same derived stats and mastery record.

`PlayerRig.intent(action)` routes UI and potion intents. `GestureDetector.sample(time, head, left, right, valid, left_target, right_target)` consumes tracking-space samples. Real locomotion/snap turns must not enter these poses. `clear_history()` is required on tracking loss, recenter, and scene changes. The test rig's `feed_simulated_pose` routes poses and named inputs into the same XR adapter without a runtime; production must leave `simulated=false`.

Health potion overlap is rejected; full heal means HP only; increasing HP/MP maxima does not refill the current amount. Low-HP mitigation checks health before the hit. These choices and the exact XP rounding are covered by tests.

## Current limits and validation

- The desktop slice has functional stats, HUD/potions, all 30 workout reps, penalty survival/death, practice grading/mastery, test controls, and original synthesized cues.
- The prototype dagger supports light attacks and defense. It does not reproduce Rickey's full heavy attack, hit-zone, crit, projectile, ragdoll, or production AI system. Bosses in training use their data-driven wind-up/damage values with simple melee stand-ins.
- Portals display unlock state but do not load full gates. No extraction, saved games, production models, or passthrough is included.
- Quest code includes core OpenXR bindings, tracked rig, wrist/world UI, ray/poke input, scroll, squat/punch detector, bottle consumption, defense, dash, and an Android preset. Hardware rendering, controller feel, deployment, and 72 FPS acceptance are pending.
- The SimulatedXR launcher uses the desktop view and F1 gesture replays. Automated tests additionally exercise the real XR rig adapter using injected poses, including tracking loss and bottle intent routing.
- Run `tools/run.ps1 -Mode Tests` for deterministic checks and `-Mode VisualTests` for a rendered/input pass. The launcher checks GDScript errors as well as exit status. See README for the process-scoped PowerShell invocation.
- Android export is currently blocked by missing Android templates, SDK, and OpenJDK on the test host. No headset was connected for acceptance. `QuestCheck` reports the prerequisites; `QuestExport` builds once they are configured.
