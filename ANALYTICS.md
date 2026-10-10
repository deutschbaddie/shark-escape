# Analytics: reading the funnels

Everything is logged on the server by `src/server/Analytics.luau` with Roblox's AnalyticsService. Open **Creator Dashboard → your game → Analytics**:
- **Funnels** has the four funnels below.
- **Economy** has coins in and out.
- **Custom events** has the counters.

Data shows up about a day after it's logged. Funnels need some traffic before the numbers mean much (100+ players).

The "target" numbers come from the launch audit's simulation of the game. They are a forecast. Replace them with your real numbers after the first week of ads.

## 1. Onboarding: is a new player getting hooked?

Logged once per brand-new player.

| Step | Logged when | Target (ad players) | If it drops here |
|---|---|---|---|
| 1 Joined | The first save loads | 100% | — |
| 2 In the water | They first ride into the sea | 90%+ | They don't see the arrow or the "Grab a sea creature" banner. Check the spawn faces the water. A loading-screen bounce shows here too. |
| 3 First catch | First creature grabbed | 85%+ | The first grab is a tap. If this still drops, add bubbles closer to the shore. |
| 4 In the tank | First creature deposited (after racing the practice shark home) | 80%+ | The practice chase scares them off or they get lost on the way back. Slow the practice shark, make the tank arrow bigger. |
| 5 Haul lesson | Brought 2 creatures home at once (or skipped after 2 min) | 75%+ | "Grab two" isn't clear. Point at a pair of bubbles close together. |
| 6 First ride | Rubber Duck bought | 70%+ | The Ride Shop is hard to find. Lower the Duck's price. |
| 7 Coral Reef | First new zone (100 speed) | 60%+ | The first real goal is too far away. Raise the early speed gain. |

The steps changed with the fun pass (the pad step and the separate shark
drill are gone). Compare only data logged after that update.

**Read it as:** the biggest drop between two steps is the next thing to fix. Fix one thing, wait 2–3 days, compare.

## 2. Zones: how deep does a run get?

One funnel per world: "Zones" (Shark Beach) and "Zones 2" (Candy Bay).
Rebirths are the Rebirth custom event, not a funnel step (logging it as
step 16 made Roblox count every zone before it as reached).

One session per rebirth run: player id plus rebirth number.

Lagoon → Coral Reef → Kelp Forest → Shipwreck Bay → Deep Blue → The Abyss → Frozen Sea → Volcano Vents → Lost City → Rebirth. The first rebirth is at Deep Blue (5K speed), then The Abyss, Frozen Sea, Volcano Vents and Lost City, so later runs reach deeper steps.

- **Target:** about 60% of runs that reach Kelp Forest should reach Shipwreck Bay.
- A cliff before one zone means its speed gate is too high for the rides available by then.
- Check **GateBlocked** (below) for the same zone: lots of bumps at its gate confirm it.
- Low Abyss → Rebirth means the rebirth reward doesn't look worth it. Make the ×1.5 easier to see, or add a rebirth-only ride.

## 3. Rides: which purchase do players stall on?

One session per run. The steps are the 15 coin rides in order; Robux rides aren't counted.

- **Target:** each step keeps 85%+ of the one before, up to the Jet Ski.
- A sharp drop at one ride means its price jumps too far past what the tank earns at that point.
- Lower that ride's price in `Config.Rides`, or make the tank slot before it cheaper.

## 4. Store: do Robux prompts convert?

One session per prompt: Prompted → Bought. The item is in custom field 1, and Pass or Product in custom field 2.

- **Healthy:** 3–8% of prompts bought. Starter Pack and Shield are usually the highest.
- An item prompted often but rarely bought: lower its price or change when it's offered.
- An item almost never prompted: it's hard to find in the UI.
- No prompts appear in a player's first 5 minutes (`Config.SHOP_UNLOCK_SECONDS`), on purpose.

## Economy (coins)

- **Coins in:**
  - TankCash: the pad, offline cash and the 2x offline product
  - IndexReward
  - GroupChest
  - Code
- **Coins out:**
  - each ride, by id
  - TankSlot
- **What to look for:**
  - If ending balances climb far above the next ride's price, players are rich with nothing to buy. That's the sign to add content or raise late prices.
  - If TankCash dwarfs everything after day 1, offline cash is too generous (the audit flagged this). Lower `Config.Offline.rate` or `maxHours`.

## Custom events

| Event | Value / field | Use it to |
|---|---|---|
| SessionMinutes | Minutes; field 1 = new or returning | Track average session length. Target 15+ min for new players. |
| SharkEaten | Field 1 = zone | Find where sharks are too hard. Compare with players per zone. |
| GateBlocked | Field 1 = zone | Players who rode into a zone below its recommended speed (its shark hunts them nonstop). Lots here = the recommended speed is too high, or the sign is unclear. |
| Rebirth | Rebirth number | Count rebirths over time. |
| DailyClaim | Day 1–7 | Day 7 claims ÷ Day 1 claims = your weekly retention hook. |
| GroupChest | 1 | Count group-chest claims (each also asks them to join the group). |
| RaidStart / RaidStolen / RaidDefended | 1 | Stolen ÷ Start should sit around 30-50%. Near 100% = owners can't get home in time (raise Config.Raid.time). |
| CloseCall | 1 | How often the shark just misses. The chase is working when this is a few per session. |
| BossReward | 1 | Players who got a Legendary from the boss Megalodon. Compare with players online during Megalodon Hour. |
| SharkDazed / BonkLoot | 1 | Noodle Bonk on a shark / loot knocked off a rider. Lots of BonkLoot with falling SessionMinutes = it feels mean: raise Config.Bonk.immune or the cooldown. |
| InvitedJoin / InviteReward | n | Friends who joined from an invite / rewards paid to inviters. Your cheapest growth: if it's near zero, make the Friends "+" more visible. |
| Quest | Field 1 = quest id | Which daily quests get finished. A quest nobody finishes needs a smaller goal. |

## Also check (built into Roblox, no code)

Analytics → Retention (D1 / D7), Engagement (session length), Acquisition (which ads bring players who stay).

- D1 retention under 10% means fix onboarding first.
- D1 is fine but D7 is under 3%: add content after about 25 minutes, as the audit says.
