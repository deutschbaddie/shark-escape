# +1 Speed to Escape the Shark

Rojo project. Untested in Studio so far.

## Run in Studio
1. In this folder: `git pull`, then `rojo serve`. In Studio, open your place and click **Connect**
   in the Rojo plugin. Rojo manages the `Shared`, `Server` and `Client` script folders. Your imported
   sharks in `ReplicatedStorage/Assets` are left alone.
2. **See the map in edit mode:** View → Command Bar, paste and press Enter:
   ```lua
   require(game.ServerScriptService.Server.World).build()
   ```
   It builds the whole map (walls, plaza, shops, gates, islands, lighting, water) into Workspace so you
   can look around. Running it again rebuilds it. On Play, the server rebuilds the map fresh anyway.
   If you've changed code since opening Studio, close and reopen the place first (Studio caches modules).
3. Game Settings: **Max Players = 8** (there are 8 docks), and turn on **Studio access to API
   services** so saving works while testing. Avatars are set to **R15** by the Rojo project
   (`StarterPlayer.GameSettingsAvatar`); ride poses need R15. Both joint types work: Motor6D rigs and
   Avatar Joint Upgrade rigs (AnimationConstraints, the default for new games).

## Uploads (one time)
- **Icons, one by one:** Studio > Asset Manager > Import each PNG in `assets/icons/single/`, right-click >
  Copy ID, and paste it next to its name in `Config.Icons.ids` (in `src/shared/Config.luau`, edited in
  your code editor, not in Studio, because Rojo overwrites Studio edits). Start with the HUD ones:
  Sneaker, Cash, Shop, Index, Rides, Tank, Rebirth, Shark. A decal id works too; the server converts it.
  Until an id is set, that icon shows an emoji.
- **Store art:** `assets/store/GameIcon.png` (512x512) and `Thumbnail.png` (1920x1080) go in
  Creator Hub > your experience > Places / Thumbnails.
- Regenerate art with `tools/icons/render.sh`. Preview all 30 creatures with
  `tools/preview/dump.py <path-to-luau>` then `tools/preview/render.py`.

## Offline checks (no Studio needed, just the Luau CLI)
- `python3 tools/preview/fit.py <path-to-luau>`: every ride against a stand-in R15 body at three
  sizes; prints any overlap and draws `tools/preview/rides.png`.
- `python3 tools/preview/ui.py <path-to-luau>`: lays out the real HUD + notifications at desktop,
  Studio, phone and tablet sizes (`tools/preview/ui_*.png`) and flags tiny text or anything off-screen.
- `python3 tools/balance/steer.py <path-to-luau>`: runs the real ride steering and compares U-turns,
  turning round from a stop and 90-degree carves with the old controller.
- `python3 tools/audio/check.py <path-to-luau> [sound-folder]`: checks every sound slot (files, layers,
  loops inside the files) and lists the files that still need an id.

## Sharks (rigged, hand-built)
- `python3 tools/shark_gen.py` writes `assets/sharks/Shark*.glb` (6 variants, 9 bones each).
- Preview: open `tools/preview.html` through a local server (`python3 -m http.server 8765 --directory tools`).
- In Studio: Import 3D on each .glb, then move the models into `ReplicatedStorage/Assets/Sharks`,
  named `SharkBaby`, `SharkHammerhead`, `SharkTiger`, `SharkGreatWhite`, `SharkMecha`, `SharkMegalodon`.
- Until they're imported, the game uses a part-built fallback shark.

## Before publishing
- Create the gamepasses and dev products and put their ids in `src/shared/Config.luau` (0 means "Soon").
  See "Robux store" below for the full list.
- The group chest uses `Config.GroupId` (set to the game's group, 902411651): the CLAIM chest in the plaza asks
  players to join it (and like the game) for a reward every 12 h. With 0 it only asks for a like.
- Sounds: upload the 33 sound files listed in ASSETS.md exactly as they are (as the game's owner) and put their ids
  in `Config.SoundFiles`; `python3 tools/audio/upload.py --key <api key> --group 902411651 --dir <folder>` does
  both. All trimming, looping, pitch and EQ happen in the game (`Config.SoundSlots`), so files never need
  re-uploading. The music is `Config.Sounds.music`.

## Look
- Studded simulator style: checkered stud walls with a grass topper down both sides of the ocean
  lane, a studded grass plaza, small shop huts (step on the glowing pad to open them), a FASTEST
  leaderboard board, blocky studded islands. Signs are sized in studs so they shrink with distance.
- UI kit (`src/client/UI.luau`): studded gradient buttons with thick outlines, dark windows with a
  studded header and red X, red "!" badges. Studs are drawn procedurally; for a crisper look upload
  `assets/textures/studs.png` as a decal and put its id in `Config.Images.Studs`.

## Features
- Onboarding (`Onboarding.luau`): grab a bubble -> dock -> collect pad -> practice shark -> first ride.
- Creature Index (`Index.luau`): 6 zones x 5 rarities, ??? silhouettes, one-time rewards, CLAIM ALL.
- Welcome Back (`Hub.luau`): the tank earns 50% while you're offline (max 6h), claim on join.
- Shark timer, zone title pop-ups, distance meter, offer banner (only once the shop unlocks).

## Robux store
The store (`Shop.openStore()` in `src/client/Shop.luau`) opens from the red Shop button on the HUD and from
the Shop hut. Sections: FEATURED (next starter pack, DOUBLE YOUR SPEED, DOUBLE YOUR CASH, codes), SPEED,
MONEY, PASSES, BOOSTS, with a category bar beside the window. Under the HUD Shop button a promo shows the
best current offer (next starter pack, else 2x Speed, else 2x Cash) once `Config.SHOP_UNLOCK_SECONDS` have
passed. Anything with id 0 shows SOON and never prompts.

Dev products (`Config.Products`, granted in `src/server/Market.luau`):

| Key | R$ | Gives |
|---|---|---|
| SpeedPack1 / 2 / 3 / 4 | 49 / 149 / 399 / 999 | speed gain per second x 600 / 2400 / 7200 / 21600 s (at least 1K / 4K / 12K / 36K speed) |
| MoneyPack1 / 2 / 3 / 4 | 49 / 149 / 399 / 999 | tank income per second x 600 / 2400 / 7200 / 21600 s (at least $1K / $5K / $20K / $75K) |
| StarterPack, ProPack, MegaPack | 49, 149, 399 | the starter ladder, one after another |
| Shield, SpeedBoost, LuckPotion, GoldenBubble, DoubleOffline | 25, 49, 49, 99, 25 | boosts |

Pack amounts come from `Config.Packs` / `Config.packAmount`, used by both the store card and the grant.
Gamepasses (`Config.Passes`): TwoXSpeed 399, TwoXCoins 199, AutoCollect 99, LuckyNet 199, BigTank 99, VIP 399,
GoldDuck 99, SharkBoard 199, RainbowSki 399.
Store icons still to make (single PNGs, ids in `Config.Icons.ids`): SpeedPack1-4 and MoneyPack1-4; until
then the cards use the Speed and MoneyBag art.

## Not done yet
- Playtest and balance pass.
- Sounds and Robux ids in `Config.luau` (empty / 0 = hidden).
