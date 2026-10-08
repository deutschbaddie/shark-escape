# +1 Speed to Escape the Shark — design sheet (REVEX)

## 1. Loop and twist
`Grab a sea creature bubble → carry it to your dock → it earns coins every second → buy a faster ride at the Ride Shop → reach deeper zones with rarer creatures`

**Twist (from the subject):** every 90 seconds the shark attacks the whole server: an 8-second "SHARK INCOMING" warning, then a hunt. A shark picks out anyone still in open water and hunts them like a real one would. First it circles them in a tightening spiral for 5 seconds (red ring on the water, arrow to the nearest sand), then it charges. If it catches them, a ~3-second cutscene plays: the shark leaps, CHOMP, and the creature they were carrying gets eaten on screen. Sand and islands are always safe, so every trip out is a risk you time.

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
- Luck: 5% chance a grab bumps up one rarity. Pity: the 3rd grab is at least Rare; the 30th is at least Epic if you've never had one.
- Tank: 4 slots, buy up to 12 (250 → 4M coins). A creature that doesn't fit sells for 20 seconds of its income.
- Index: 6 zones × 5 rarities. Each first discovery pays a one-time reward (coins plus speed).
- Rebirth at 25K speed: resets speed, coins and rides, and gives a permanent ×1.5.
- Offline: the tank earns 50% while you're away (max 6h), claimed on the Welcome Back screen.

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
- Core loop with server authority (rolls, cash and purchases on the server; `ProcessReceipt` with receipt dedupe). Saves on leave, autosaves and saves on shutdown.
- 6 zones with hard gates, 54 islands, server-wide shark attacks: a warning breach, hunt, circling islands, bite cinematic.
- 6 hand-built rigged sharks (`tools/shark_gen.py`), with a part-built fallback until they're imported.
- 15 rides, each with its own handling (`Config.RideFeel`) and pose (stand / sit / straddle / prone / float). No walk cycle on water.
- Ride Shop building (rides are bought there), Shop and Index huts with step-on pads, FASTEST global leaderboard board.
- Onboarding: bubble → dock → pad → practice shark → Ride Shop.
- Creature Index, Welcome Back offline earnings, rebirth with a confirm screen.
- Studded simulator UI kit, a 32-icon custom set, stud texture, mobile layout for touch screens.

**Cut / not yet:** music and most sound effects (need Creator Store ids), trading, pets, daily rewards (REVEX: only if the loop needs them).

## 5. Playtest notes (to do in Studio; nothing here has been played yet)
- Check the R15 ride poses on every stance; adjust `Water.luau` POSES if a body part clips the ride.
- Feel each ride's handling; tune `Config.RideFeel`.
- Compare real pacing with the sim; adjust ride prices or gains if rebirth lands far from ~25 min.
- Watch the first minute with a new player: they should grab a bubble within 10 s.

## TikTok recap
*"I had 4 hours to make +1 Speed to Escape the Shark… and the shark is the only thing faster than you."*
