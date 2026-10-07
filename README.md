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
3. Game Settings: **Avatar = R15**, **Max Players = 8** (there are 8 docks), and turn on
   **Studio access to API services** so saving works while testing.

## Uploads (one time)
- Icons: Asset Manager → Import → `assets/icons/IconsA.png` and `IconsB.png`. Right-click each →
  Copy ID, then paste them into `Config.Icons.SheetA` / `SheetB` as `"rbxassetid://<id>"`. Until then
  the game shows emoji.
- Store art: `assets/store/GameIcon.png` (512×512) and `Thumbnail.png` (1920×1080) go in
  Creator Hub → your experience → Places / Thumbnails.
- Regenerate any art with `tools/icons/render.sh` (needs Python + Chromium).

## Sharks (rigged, hand-built)
- `python3 tools/shark_gen.py` writes `assets/sharks/Shark*.glb` (6 variants, 9 bones each).
- Preview: open `tools/preview.html` through a local server (`python3 -m http.server 8765 --directory tools`).
- In Studio: Import 3D on each .glb, then move the models into `ReplicatedStorage/Assets/Sharks`,
  named `SharkBaby`, `SharkHammerhead`, `SharkTiger`, `SharkGreatWhite`, `SharkMecha`, `SharkMegalodon`.
- Until they're imported, the game uses a part-built fallback shark.

## Before publishing
- Create the gamepasses and dev products and put their ids in `src/shared/Config.luau` (0 means "Soon").
- Choose sounds from the Creator Store and put their ids in `Config.Sounds`. Record every asset id in ASSETS.md.

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

## Not done yet
- Playtest and balance pass.
- Sounds and Robux ids in `Config.luau` (empty / 0 = hidden).
