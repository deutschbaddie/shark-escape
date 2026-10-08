# Assets

Every asset the game uses, with its id and source. Never add an id that hasn't been checked.

| What | Id | Source | Where it's used |
|---|---|---|---|
| Stud texture (image) | `rbxassetid://6927295847` | "Studs" by aetoreous, Creator Store decal 6927295857, public domain | `Config.Images.Studs`: UI panels and buttons, and stud textures on parts |
| Icons (34 single files) | _upload_ `assets/icons/single/*.png` | Made for this game (`tools/icons/make_icons.py`) | `Config.Icons.ids` |
| Sharks ×6 | _import_ `assets/sharks/*.glb` | Made for this game (`tools/shark_gen.py`) | `ReplicatedStorage/Assets/Sharks` |
| Game icon / thumbnail | _upload_ `assets/store/*.png` | Made for this game (`tools/icons/make_store_art.py`) | Experience settings |
| Sounds | `rbxasset://sounds/impact_water.mp3`, `action_swim.mp3`, `impact_explosion_03.mp3`, `electronicpingshort.wav` | Built into the Roblox client | `Config.Sounds` |

## Sounds still to choose (35)

Paste each id into `Config.Sounds` in `src/shared/Config.luau` and add a row to the table above. Empty slots are silent. For music, use the Creator Store's licensed tracks from Roblox (free to use); never upload copyrighted songs. Ride loops should be seamless 2–6 s loops: the game sets their pitch and volume from your speed.

| Slot | Should sound like | Plays when |
|---|---|---|
| `musicBeach` | Chill tropical (ukulele or steel drums), 1–2 min loop | On land: dock, plaza, shops |
| `musicOcean` | Upbeat summer adventure | Out on the water |
| `musicDeep` | Mysterious, slower, underwater pads | Deep Blue and The Abyss |
| `musicHunt` | Tense chase: fast drums, low strings | Shark warning and hunt |
| `ambWaves` | Gentle waves loop | Always (louder at sea) |
| `ambGulls` | Seagulls, distant beach | Near the shore |
| `uiClick` | Soft bubbly pop | Every button |
| `uiOpen` / `uiClose` | Light swoosh-pop / short reverse pop | Windows open / close |
| `uiError` | Cartoon "bonk" | Can't afford it, locked gate, bad code |
| `uiToast` | Tiny soft ding | Small messages |
| `uiTakeover` | Whoosh into an impact | Big moments (new zone, new ride, Legendary) |
| `grabRare` | Sparkly chime | Rare and Epic grabs |
| `legendary` | Short fanfare or choir "aah" | Legendary grab |
| `lucky` | Slot-machine "ding-ding" | LUCKY! rarity bump |
| `discover` | Page flip into a ding | New Index entry |
| `deposit` | Water "bloop" | Creature goes in the tank |
| `rideNew` | Upgrade fanfare with an engine rev | New ride |
| `zoneUnlock` | Gate opening into a triumphant hit | New zone |
| `rebirth` | Rising power-up whoosh | Rebirth |
| `sharkAlarm` | Alarm horn, 2–3 s | SHARK INCOMING |
| `sharkCharge` | Aggressive underwater whoosh or roar | The shark charges |
| `dodge` | Fast whoosh past | DODGED! |
| `spat` | Cartoon spit, "ptooey" | Washed up on the beach |
| `rideSplash` | Paddling splashes | Pool Noodle, Inner Tube, Giant Donut |
| `rideDuck` | Light paddling with rubber squeaks | Rubber Duck, Golden Duck |
| `duckSqueak` | One squeak (one-shot) | Hopping into the water on a duck |
| `rideKick` | Kicking splashes | Boogie Board |
| `rideSurf` | Rushing water, carving waves | Surfboard, Shark Board |
| `rideBubbles` | Bubbly fizz | Bathtub |
| `rideMotor` | Small outboard motor | Banana Boat |
| `rideJetSki` | Jet ski engine | Jet Ski, Rainbow Jet Ski (pitched up) |
| `rideBoat` | Speedboat engine | Speedboat |
| `rideDolphin` | Water rush with dolphin clicks | Dolphin |
| `rideRocket` | Rocket thruster roar | Rocket Surfboard |

`grab`, `coin`, `buy`, `chomp`, `splash` and `swim` already use built-in Roblox sounds; replacing them is optional.
