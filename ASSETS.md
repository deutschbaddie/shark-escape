# Assets

Every asset the game uses, with its id and source. Never add an id that hasn't been checked.

| What | Id | Source | Where it's used |
|---|---|---|---|
| Stud texture (image) | `rbxassetid://6927295847` | "Studs" by aetoreous, Creator Store decal 6927295857, public domain | `Config.Images.Studs`: UI panels and buttons, and stud textures on parts |
| Icons (34 single files) | _upload_ `assets/icons/single/*.png` | Made for this game (`tools/icons/make_icons.py`) | `Config.Icons.ids` |
| Sharks ×6 | _import_ `assets/sharks/*.glb` | Made for this game (`tools/shark_gen.py`) | `ReplicatedStorage/Assets/Sharks` |
| Game icon / thumbnail | _upload_ `assets/store/*.png` | Made for this game (`tools/icons/make_store_art.py`) | Experience settings |
| Built-in sounds | `rbxasset://sounds/impact_water.mp3`, `action_swim.mp3`, `impact_explosion_03.mp3`, `electronicpingshort.wav` | Built into the Roblox client | `Config.Sounds`: fallbacks until the files below have ids |

## Music

| What | Id | Source | Where it's used |
|---|---|---|---|
| Main music | `rbxassetid://1846088038` | Picked by the developer on Roblox | `Config.Sounds.music`: plays everywhere; ducks during shark hunts |

`musicBeach`, `musicOcean`, `musicDeep` and `musicHunt` are optional: fill one to give that place its own track.

## Sound files (33)

Upload these files exactly as they are, as the game's owner (a game can only play audio its owner uploaded), then put each id in `Config.SoundFiles`. `python3 tools/audio/upload.py` does both in one go (see its header). Every edit happens in the game (`Config.SoundSlots`: which part plays, loop points, pitch, EQ, layers, fades, loudness), so nothing needs re-uploading. `python3 tools/audio/check.py <luau> <folder>` checks the setup against the files.

Licenses are as the source listings give them (checked by the developer when downloading). Freesound files are CC0. Mixkit files are under the [Mixkit Sound Effects Free License](https://mixkit.co/license/modal/sfxFree/); to be safe, keep them private (don't distribute them on the Creator Store).

| File | Source | Used for | Id |
|---|---|---|---|
| `mixkit-soap-bubble-sound-2925` | Mixkit #2925 | uiClick (first pop only) | `rbxassetid://91161037960580` |
| `mixkit-explainer-video-pops-whoosh-light-pop-3005` | Mixkit #3005 | uiOpen; uiClose (same pop, pitched down) | `rbxassetid://132051161428247` |
| `mixkit-boing-hit-sound-2894` | Mixkit #2894 | uiError (first 0.5 s) | `rbxassetid://81137746729164` |
| `mixkit-dry-pop-up-notification-alert-2356` | Mixkit #2356 | uiToast | `rbxassetid://130268760790939` |
| `mixkit-movie-whoosh-impact-presentation-2903` | Mixkit #2903 | uiTakeover; under rebirth | `rbxassetid://93945704934482` |
| `mixkit-water-bubble-1317` | Mixkit #1317 | grab (with a splash layered under) | `rbxassetid://109536715402499` |
| `mixkit-sea-water-splash-1198` | Mixkit #1198 | splash (water entry, 3D for other riders); under grab and the shark charge | `rbxassetid://78768880176281` |
| `mixkit-fairy-magic-sparkle-871` | Mixkit #871 | grabRare | `rbxassetid://124096247708665` |
| `mixkit-successful-horns-fanfare-722` | Mixkit #722 | legendary | `rbxassetid://116467160770080` |
| `mixkit-melodic-bonus-collect-1938` | Mixkit #1938 | lucky | `rbxassetid://114365963704853` |
| `mixkit-page-forward-single-chime-1107` | Mixkit #1107 | discover | `rbxassetid://93383166774303` |
| `mixkit-liquid-bubble-3000` | Mixkit #3000 | deposit (3D at your tank) | `rbxassetid://78767914886421` |
| `mixkit-clinking-coins-1993` | Mixkit #1993 | coin | `rbxassetid://133067320326955` |
| `mixkit-money-bag-drop-1989` | Mixkit #1989 | collect (cash pad) | `rbxassetid://94615652928279` |
| `184438__capslok__cash-register-fake` | [Freesound 184438](https://freesound.org/s/184438/), CC0 | buy | `rbxassetid://128288863011143` |
| `mixkit-unlock-new-item-game-notification-254` | Mixkit #254 | rideNew | `rbxassetid://90531968965473` |
| `mixkit-achievement-completed-2068` | Mixkit #2068 | zoneUnlock; rebirth (pitched down + whoosh) | `rbxassetid://94011401770356` |
| `mixkit-facility-alarm-sound-999` | Mixkit #999 | sharkAlarm (first 2 s, faded) | `rbxassetid://119351650727606` |
| `mixkit-aggressive-beast-roar-13` | Mixkit #13 | sharkCharge (3D at the shark; deeper, darker EQ, splash under) | `rbxassetid://133338904418165` |
| `528962__steenish__crunch` | [Freesound 528962](https://freesound.org/s/528962/), CC0 | chomp (3D; deeper, splat under) | `rbxassetid://114947460738011` |
| `445118__breviceps__cartoon-splat` | [Freesound 445118](https://freesound.org/s/445118/), CC0 | spat; under chomp | `rbxassetid://87181834248801` |
| `mixkit-arrow-whoosh-1491` | Mixkit #1491 | dodge | `rbxassetid://97268804826952` |
| `350917__csaszi__rubber-duck-csg` | [Freesound 350917](https://freesound.org/s/350917/), CC0 | duckSqueak (one squeak; also now and then while riding a duck) | _upload_ |
| `456151__jfournier18__dolphin-noise` | [Freesound 456151](https://freesound.org/s/456151/), CC0 | dolphin calls now and then while riding the Dolphin | `rbxassetid://96059363771818` |
| `mixkit-sea-swimming-loop-1181` | Mixkit #1181 | rideSplash, rideKick, rideDolphin (different loops) | `rbxassetid://131576493971250` |
| `188199__splicesound__paddle-boat-on-water-2` | [Freesound 188199](https://freesound.org/s/188199/), CC0 | rideDuck | `rbxassetid://79089636097979` |
| `443870__eardeer__water_flow_dam_close_loop` | [Freesound 443870](https://freesound.org/s/443870/), CC0 | rideSurf (less rumble) | `rbxassetid://123327977782557` |
| `mixkit-deep-water-bubbles-1321` | Mixkit #1321 | rideBubbles; ambTank (slow bloops at every dock) | `rbxassetid://76938595911508` |
| `454199__kyles__speed-boat-outboard-motor-medium-high-gear-waves-splash` | [Freesound 454199](https://freesound.org/s/454199/), CC0 | rideBoat; rideMotor (another part, pitched down) | `rbxassetid://117099041120300` |
| `212441__wjauch__jetski` | [Freesound 212441](https://freesound.org/s/212441/), CC0 | rideJetSki (steady high-revs part) | _upload_ |
| `171106__qubodup__rocket-flight-loop` | [Freesound 171106](https://freesound.org/s/171106/), CC0 | rideRocket | _upload_ |
| `mixkit-sea-waves-loop-1196` | Mixkit #1196 | ambWaves (open-sea bed); ambShore (3D small waves along the shore and around islands) | `rbxassetid://110907888719466` |
| `seagulls_distant` | [Freesound 537854](https://freesound.org/s/537854/) (Ambientsoundapp), CC0 | ambGulls (3D over the beach and the nearest palm island) | `rbxassetid://94208672690861` |

Not downloaded: the outboard motor (Freesound 637202, 20.9 MB, over Roblox's 20 MB limit; the Banana Boat uses part of the speedboat instead) and the rising power-up for rebirth (Freesound 466833; rebirth uses the achievement sound pitched down with a whoosh).

`swim` still uses the built-in Roblox sound. Until a file has an id, `grab`, `coin`, `buy`, `chomp` and `splash` use built-in Roblox sounds; everything else stays silent.
