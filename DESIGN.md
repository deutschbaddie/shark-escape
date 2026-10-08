# +1 Speed to Escape the Shark — design sheet (REVEX)

## 1. Loop and twist
`Grab a sea creature bubble → carry it to your dock → it earns coins every second → buy a faster ride at the Ride Shop → reach deeper zones with rarer creatures`

**Twist (from the subject):** about every 80 seconds the shark attacks the whole server: a 5-second "SHARK INCOMING" warning, then a 22-second hunt. A shark picks out anyone still in open water and hunts them like a real one would. First it circles them once in a tightening spiral (red ring on the water, arrow to the nearest sand), then it charges. The charge is always faster than you, but it turns in a wide circle: reach sand or an island, or swerve at the last second so it overshoots ("DODGED!") and has to come round again. If it catches you, a ~3-second cutscene plays where you were bitten: the shark leaps, CHOMP, and the creature you were carrying gets eaten on screen, then you wash up on the beach. Sand and islands are always safe, but while the shark hunts every grab is luckier (+30% chance to bump a rarity), so staying out is a real gamble.

Speed is the stat (+1 game): it climbs every second, faster with better rides. Zones are gated at round numbers: **100 · 500 · 1K · 5K · 25K**.

## 2. Ladder (real numbers, `src/shared/Config.luau`)
Rides: speed gain ×~1.35 per step (REVEX income step). Prices step ×~3.4 instead of ×1.6, because creature income jumps ×5 per zone and has to be matched.

| # | Ride | Price | +Speed/s |
|---|---|---|---|
| 1 | Pool Noodle | free | 1 |
| 2 | Rubber Duck Floatie | 25 | 2 |
| 3 | Inner Tube | 85 | 3 |
| 4 | Boogie Board | 300 | 4 |
| 5 | Surfboard | 1,000 | 5 |
| 6 | Bathtub | 3,300 | 7 |
| 7 | Banana Boat | 11,000 | 9 |
| 8 | Jet Ski | 38,000 | 12 |
| 9 | Speedboat | 130,000 | 16 |
| 10 | Dolphin | 450,000 | 22 |
| 11 | Giant Donut | 1,500,000 | 30 |
| 12 | Rocket Surfboard | 5,000,000 | 40 |

| Zone | Gate (speed) | Creature value | Shark |
|---|---|---|---|
| Lagoon | 0 | ×1 | Baby |
| Coral Reef | 100 | ×5 | Hammerhead |
| Kelp Forest | 500 | ×25 | Tiger |
| Shipwreck Bay | 1,000 | ×120 | Great White |
| Deep Blue | 5,000 | ×600 | Mecha |
| The Abyss | 25,000 | ×3,000 | Megalodon |

- Rarity odds: Common 60 · Uncommon 25 · Rare 10 · Epic 4 · Legendary 1 (%), values ×1 · ×3 · ×10 · ×40 · ×200.
- Mutations: Gold ×2 (3%) · Diamond ×5 (1%) · Rainbow ×10 (0.3%).
- Luck: 5% chance a grab bumps up one rarity (+30% while the shark hunts). Pity: the 3rd grab is at least Rare; the 30th is at least Epic if you've never had one.
- Size and weight: every creature rolls a size: most are 0.75x to 1.3x, 4% are Big (1.4x to 1.9x) and 0.8% are Huge (2x to 3x, shown on the bubble from far away). Weight is the species' usual weight times size. Income scales with the square root of size, and big ones look bigger in the tank.
- Tank: 4 slots, buy up to 12 (250 → 4M coins). A creature that doesn't fit sells for 20 seconds of its income.
- Index: 6 zones × 5 rarities. Each first discovery pays a one-time reward (coins plus speed).
- Rebirth at 25K speed: resets speed, coins and rides, and gives a permanent ×1.5.
- Offline: the tank earns 30% while you're away (max 24h), claimed on the Welcome Back screen.

### Pacing (simulation: `python3 tools/balance/pacing.py`, perfectly efficient player)
| Milestone | Median | REVEX target |
|---|---|---|
| First upgrade (Duck) | 0:36 | < 60 s ✅ |
| First Rare | 0:46 | 3 min ✅ |
| Coral Reef unlocked | 1:02 | 3 min ✅ |
| Shipwreck Bay | 4:01 | — |
| Deep Blue | 9:18 | 10 min big goal ✅ |
| All 12 rides | 15:57 | — |
| Rebirth ready / Abyss | 19:39 | ~25 min ✅ (real players are slower than the sim) |

These are model numbers, not playtest results. Tune them after real sessions.

## 3. Shop (Robux; ids are 0 until created, which hides the button)
| Sells | Item | Type | R$ |
|---|---|---|---|
| TIME | 2x Speed | Pass | 399 |
| TIME | 2x Coins | Pass | 199 |
| TIME | Auto Collect | Pass | 99 |
| TIME | 2x Speed (15 min) | Product | 49 |
| TIME | 2x Offline Coins | Product | 25 |
| LUCK | Lucky Net (+15% upgrade chance) | Pass | 199 |
| LUCK | Luck Potion (10 min) | Product | 49 |
| LUCK | Golden Bubble (Rare 70 · Epic 25 · Legendary 5 %, odds shown) | Product | 99 |
| SPACE | +4 Tank Slots | Pass | 99 |
| STYLE | VIP (gold wake, tag, +10% coins) | Pass | 399 |
| STYLE | Golden Duck ×1.25 / Shark Board ×1.5 / Rainbow Jet Ski ×2 | Pass | 99 / 199 / 399 |
| — | Shark Shield (survive one bite) | Product | 25 |
| — | Starter Pack (Rare Octopus + 30 min 2x Speed + 3 Shields) | Product | 49 |

Honesty rules in code: no Robux prompts or offers in the first 5 minutes, paid random items show their odds, no fake timers, and a free player can finish everything.

## 4. What got built
- Core loop with server authority (rolls, cash and purchases on the server; `ProcessReceipt` with receipt dedupe). Saves on leave, autosaves and saves on shutdown; old saves migrate.
- **30 creatures**, 5 per zone, each built from studded blocks and animated (tails, fins, tentacles, legs, wings).
- **Hold-to-grab prompts:** rarer creatures take longer to grab (0.35s to 1.5s), so the shark is a real risk. Every prompt has the custom style (key circle, filling ring, white outline on the target). The very first grab is a tap (big pulsing "TAP!" / "PRESS E!"); until your first held grab, prompts show "HOLD!" over a pulsing ghost ring and "KEEP HOLDING!" if you let go early.
- **Tank collection (Steal-an-Egg style):** everything you catch is kept (up to 40). The best are Active and swim in a showcase tank with $/s tags that show through the glass. Hover over a creature (or tap it on mobile) to outline it and see its name, rarity, weight and $/s. The **View Tank** prompt on the back of every tank opens a close-up camera: drag to look around, scroll or pinch to zoom, walk away to leave. Tank panel with X/Y Active, +1 EQUIP, Equip/Unequip, Equip Best. Better catches swap in automatically.
- **Offline earnings:** the tank earns 30% while you're away (max 24h). "$X/day offline" is shown on your tank sign, at your dock, and when you open the menu to leave. Welcome Back claim on return.
- **Friend Boost** (+10% coins per friend in the server, max +50%) with an invite button. **Slow Mode** toggle for precise grabs at high speed. **Codes** (in the Shop). Player list shows Money/s and Speed.
- 6 zones with hard gates, 54 islands, server-wide shark attacks: a shark circles you, charges, and plays the bite cutscene.
- 15 rides, each with its own handling and pose; no walk cycle on water. The rider is fitted to the ride by forward kinematics on their real avatar joints (`Rig.luau`), and the server scales the ride to the avatar's leg length, so the body sits on the seat, in the tube or on the deck at any body size. Joints are found by class (Motor6D or the AnimationConstraints of Avatar Joint Upgrade rigs, the default for new games) and named by the body part they move. `tools/preview/fit.py` checks every ride against a stand-in R15 body (0 overlap at 0.9x, 1x and 1.12x). The project forces R15 avatars. Ride Shop building (rides are bought there).
- **Steering** (camera-relative, like walking): the nose turns toward your stick and the speed follows it (a little slides out on low-grip rides); turns are quicker when slow. Pushing back while moving brakes, spins round in under half a second and launches you back to full speed. Pushing back from a stop reverses (a tap backs up a few studs); keep holding and it swings round and drives off. After a turn-around the target stays put until you move the stick, so a phone's Follow camera can't make you circle. `tools/balance/steer.py` compares it with the old controller (U-turns about 3x faster, a fifth of the overshoot).
- **One notification hierarchy (`Notify.luau`):** takeovers (shark incoming, new zone, new ride, legendary) clear the whole screen for a moment; punch words (LUCKY!, DODGED!, PTOOEY!) share the center and never stack; one top banner at a time by priority (shark status > tutorial step > zone name); at most two small toasts; a quiet status line (distance at sea, $/day offline when you're at your dock or open the menu). Everything fades with its outline.
- Shop / Index / Ride Shop buildings with step-on pads. HUD buttons teleport you a few steps in front of the pad, facing it, with a "Walk in!" arrow. FASTEST leaderboard board.
- Onboarding: a big welcome, then numbered steps ("STEP 2 of 5 · Bring it home") with a 3D arrow, a short cheer between steps, a practice shark that circles then charges (slow to turn, so you can swerve), and "YOU'RE READY!" at the end. The first grab is an instant tap; the hold is taught on the next one. Caught by the practice shark once: it comes back slower and the arrow points straight at the sand. Caught twice: "You'll get it next time!" and the tutorial moves on.
- Studded simulator UI kit in the Steal-an-Egg style: small wide buttons on the left, small icon squares on the right (drawn tank icon, boosts with time left above them), one $ (the font's). Scaled for every screen from a 1280x720 canvas (phones get 1.3x for thumbs); `tools/preview/ui.py` lays out the real HUD at desktop, Studio, phone and tablet sizes.

- **Daily Rewards:** 7-day streak calendar (cash, shield, 2x speed, luck, big cash, Epic creature, Huge Legendary on day 7); claim every 20 h, the streak restarts after 48 h. Opens by itself once per session when ready, and from the gift square.
- **Group chest:** a CLAIM chest in the plaza, "Join Group & Like To Claim!", every 12 h for about 3 minutes of tank income plus 10 minutes of 2x speed. Group membership is checked on the server.
- **Audio system (3D):** one main music track (optional tracks per place; a hunt ducks the music). Small waves lap all along the shoreline in 3D and swell with the foam you see; the nearest islands have their own waves, gulls circle over the beach and the nearest palm island, every dock's tank bubbles, and the open-sea bed rises as you head out. Every rider's ride loops in 3D on their body (pitch and volume follow speed; the Dolphin clicks and ducks squeak now and then), other riders' splashes, the shark's roar and the chomp are positioned too. The 33 source files are uploaded as they are; trimming, loop points, pitch, EQ, layers and loudness are all done in game (`Config.SoundSlots`, `Sounds.luau`), so changes never need a re-upload.
- **World:** tall checker walls with two grass terraces and voxel trees and palms behind them; zone barriers are a shimmer wall with a sign (zone, speed needed, your speed) and a buoy line.

**Cut / not yet:** sound ids (35 to pick, listed in ASSETS.md), stealing from other players, trading. The launch audit (`tools/balance/audit.py`) recommends capping offline cash and adding rebirth-gated content next.

## 5. Playtest notes (to do in Studio; nothing here has been played yet)
- Check the ride poses on a few avatars (blocky, Rthro, small). The fit is solved from the real joints, but the stand-in rig in `fit.py` is an approximation; tweak `Rig.POSES` / `Rides.FIT` if anything sinks in.
- Shark feel: try running, hiding and swerving in every zone (`Config.Shark`: warning, stalk, chargeVsPlayer, chargeRadius).
- Feel each ride's handling; tune `Config.RideFeel`.
- Compare real pacing with the sim; adjust ride prices or gains if rebirth lands far from ~25 min.
- Watch the first minute with a new player: they should grab a bubble within 10 s.

## TikTok recap
*"I had 4 hours to make +1 Speed to Escape the Shark… and the shark is the only thing faster than you."*
