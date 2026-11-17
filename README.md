# SKIvSKI

Two teams ski down a random slope and shoot each other with paintballs. A Creation for Other5, and a **teaching
game**: all of the gameplay is Blueprints (no C++), built on what Other5 already gives every Creation (the combat
character, the Game Coordinator, remappable controls, the game menu). Read the graphs as text in `Docs/Graphs`.

Status (2026-11-09): a playable vertical slice. See [Status](#status) for what works, what's stubbed and the open
questions.

## Play it

- **In the editor:** open `/SKIvSKI/Maps/L_SkiVSki` and press Play. Other5's usual "Play as Client" (dedicated server
  plus clients) should work: it wasn't tried in PIE, but the same setup was tested with separate processes (Tests).
- **Standalone game from the editor build:**
  `UnrealEditor.exe Other5.uproject /SKIvSKI/Maps/L_SkiVSki -game -windowed -NoEOS`
- **Server options:** `-SkiDifficulty=Easy|Medium|Hard` (the starting slope), `-SkiPracticeHits` (paint hits in the
  lobby score too, to try scoring without racing).

A round: **Lobby** (15 s on the flat snow behind the gates; the clock waits for the first player) → **Countdown**
(4 s, frozen behind your team's gate) → **Race** (until everyone crosses the finish, or 150 s) → **Results** (10 s)
→ a new lobby on a **new random slope**.

### Controls (all in Settings > Controls, so players can change them)

| Key (pad) | What it does |
|---|---|
| W (left stick up) | Turn the skis toward the fall line (straight downhill): go faster. On flat snow, skate forward. |
| S (left stick down) | Turn the skis away from the fall line the short way: across the slope (a quick stop, held there for a moment), then on round until they point uphill, and you slide backwards. |
| A / D (left stick) | Steer left / right. |
| Mouse | Look and aim (the upper body follows; the skis don't). |
| Left mouse (right trigger) | Fire: once per click (semi-auto), or held (full-auto markers), up to the gun's rate. |
| R (Y) | Reload (an empty magazine reloads by itself). |
| B (Start) | The store (lobby and results; it opens by itself with the results). Click an item to buy it. |
| T (X) | Switch team (lobby only). |
| [ / ] (d-pad) | Admin: easier / harder slope (lobby or results; regenerates the slope). Without an AdminPIN on the server everyone is an admin. |
| Space | Jump (from Other5Combat). |
| Esc / F10 | Other5's game menu. |

### Paint, outs and scoring

- A paintball hit on the **other** team during the race puts that skier **OUT** for the rest of the race: grey helmet
  and skis, can't fire, no finish points (they can still ski down). "Hit!" rises over them in the shooter's colour.
- Like real paintball, a ball can **bounce** off instead: each hit bounces with the shooter's **paint bounce chance**
  (10% with standard paint, shown on your HUD). A bounce ricochets off the skier, doesn't put them out, and shows
  "Bounce!". Better paint, bought between runs, will lower it (and can look different).
- Points: **1** (`HitPoints`) per opponent you put out; crossing the finish (not out) **10, 8, 6, 5, 4, 3, 2, 1**
  (`FinishPoints`) for 1st, 2nd... Points go to your team; most points wins the round.
- **Coins**, for the store: **3** (`HitCoins`) for each opponent you put out, **10** (`SurviveCoins`) for getting through a race
  without being put out. You keep them while you're connected; everyone starts (or joins) with none and the basic gear.
- Your **paint bounce chance** (10%) is on your player state too.
- Paint doesn't hurt (no health loss, no deaths): this is a race.

### The store (between runs)

In the lobby and with the results (B, or it opens by itself with the results) the store sells markers, skis and ski
wax for coins. You ski with what you bought: no switching guns mid-run. What you've bought stays yours while you're
connected, so clicking it again puts it back on for free. The first of each is everyone's, free.

| Markers | Price | Fire | Magazine, reload | |
|---|---|---|---|---|
| Splat Pistol | free | semi-auto, up to 5/s | 10, 1.4 s | Everyone's first marker. |
| Snap Marker | 12 | semi-auto, up to 8/s | 16, 1.8 s | As quick as you click; the most accurate, the fastest balls. |
| Stream Marker | 20 | full-auto, 11/s | 30, 2.4 s | Hold to spray; less accurate. |
| Scattergun | 16 | 6 balls a pump, 1.3/s | 5, 2.6 s | Hard to miss up close. |

| Skis | Price | Top speed | Turning | Grip (carving, edges) | Stopping (skids) | Snow friction |
|---|---|---|---|---|---|---|
| Rental Skis | free | 100% | 100% | 100% | 100% | 100% |
| Slalom Skis | 15 | 95% | 135% | 130% | 150% | 100% |
| Downhill Skis | 18 | 112% | 80% | 90% | 85% | 80% |

| Wax | Price | Snow friction |
|---|---|---|
| Factory Wax | free | 0.02 |
| Glide Wax | 6 | 0.014 |
| Race Wax | 14 | 0.008 |

| Upgrades | Price | Does | |
|---|---|---|---|
| Extended Hopper | 10 | magazine +50% (any gun) | Half as many balls again before you reload. |
| Extended Reloads | 8 | +3 spare magazines a run | Run dry later. |

Upgrades are on for good once bought. Everyone carries `BaseSpareMags` (3) spare magazines of the gun's own size; the
paint fills up whenever the round moves on, so you can run out mid-run (OUT OF PAINT) but start every run full.

## How it works

Everything is in `Content/` (Blueprints, data, materials, one level). C++: none in this plugin; Other5 gives the base
classes and the shared **teams** (`Other5Teams.h`, Other5 `Docs/Teams.md`): `BP_SkiGameMode` lists the teams (Red,
Blue), new players join the smaller one, and the Blueprints use the **Other5|Teams** nodes (Get Team, Team Color,
Team Name, Team Score, Add Team Score, Request Team, Set Team Switch Allowed...).

| Piece | What it is |
|---|---|
| `Blueprints/BP_SkiCharacter` | The skier: a child of Other5Combat's `BP_Other5ProjectileCharacter` (camera, health, skins, game menu) with skis, a team-coloured helmet and a paintball gun. Movement, firing, team colours. |
| `Blueprints/BP_SkiSlope` | The random slope: builds snow, pines, start gates and the finish from `Seed` + `Difficulty`. |
| `Blueprints/BP_SkiDirector` | Rounds and teams: a child of Other5's **Game Coordinator** (`AOther5GameCoordinator`), placed once in the level. |
| `Blueprints/BP_SkiPlayerState` | Each player's outs scored (`Hits`), points, finish place, whether they're out (`bOut`), coins, and gear: what they have on (`GunIndex`, `SkisIndex`, `WaxIndex`, the wax's `SnowFriction`), what they've bought (`Owned`), `BounceChance` (child of `Other5BasePlayerStateGAS`, whose `TeamId` is the team). |
| `Blueprints/BP_Paintball` | One paintball. |
| `Guns/BP_PaintGunData`, `Guns/DA_Paint*` | Gun data: a Blueprint Primary Data Asset class and the four markers. |
| `Gear/BP_SkiData`, `Gear/BP_WaxData`, `Gear/DA_Skis*`, `Gear/DA_Wax*` | The store's skis and ski wax (`SetupGear.py`). |
| `Blueprints/BP_SkiHUD` | The round panel and team scores, the GET READY countdown, GO!, the results scoreboard, your skier and gear panels, the "Hit!" / "Bounce!" pop-ups and the round sounds, drawn on the canvas in Other5's UI style (child of Other5's game HUD `BP_Other5GameHUD`: menu and chat, none of Combat's ammo, grenade, health or credits widgets). |
| `Audio/S_Ski*` | The game's own sounds (hit, bounce, countdown beep, go, score chime, results fanfare), synthesised by `Docs/Scripts/SetupAudio.py` (sources in `Docs/Audio`). The shots are Other5Combat's rifle sounds. |
| `Blueprints/BP_SkiGameMode` | Pawn, player state, controller and HUD classes, and the **Teams** list (child of `Other5GameModeBase`). |
| `Animation/ABP_Skier` | The skier's Animation Blueprint. |
| `Input/IA_Ski*`, `IMC_SkiVSki` | The controls (player-mappable, `SKIvSKI.*` names). |
| `Materials/` | Snow, one colour material (team colours, pines, paintballs) and the paint splat decal. All node-built, no textures. |
| `Maps/L_SkiVSki` | The game level. `L_SkiTest` is a plain 20° ramp for trying the movement. |
| `PAL_SKIvSKI` | Primary Asset Label: the creation's content cooks into **chunk 1021**. |

### Skiing (BP_SkiCharacter, `Docs/Graphs/BP_SkiCharacter.Movement.lisp`)

The skis point along `SkiYaw`; the body faces the same way, the camera is free. Every frame (on the player's own
machine) the character:

1. **Looks down** (`UpdateSlope`): a line trace gives the snow's normal. Its flat part points down the fall line
   (`FallLineYaw`) and its length is sin(slope) (`SlopeDegrees`).
2. **Steers** (`SteerSkis`): W turns toward the fall line, S away from it (pausing `AcrossHoldSeconds` across the
   slope), A/D directly, at `TurnRate` degrees a second. The new yaw goes to the server with `ServerSetSkiYaw` (a
   Run on Server event), which turns the character there so everyone else sees it.
3. **Lets gravity pull** (`PushDownSlope`), as on real skis:
   - along the skis: `Gravity` × sin(slope) × cos(angle to the fall line), less snow friction (the player's
     `SnowFriction` gear × `Gravity` × cos(slope); `GetSnowFriction`). Skis down the fall line: almost no friction.
   - across the skis: the edges hold, up to `EdgeGrip` × `Gravity` × cos(slope), so skis across the slope keep you
     standing still; on a slope steep enough to beat the edges (about 29° with EdgeGrip 0.55) you side-slip down.
   Each pull becomes **Add Movement Input** (backwards when the skis point uphill), scaled by `FullInputAccel`.
   On flat snow, W skates up to `SkateSpeed`.

Character Movement does the rest, and because only Add Movement Input drives it, its client prediction and server
correction work as for walking:

- acceleration = Max Acceleration × input. **Min Analog Walk Speed** is set to `TopSpeed`: without it the speed
  would top out at Max Walk Speed × input, so a gentle pull meant a low top speed (skiing used to be slow for that
  reason). Now the speed keeps building up to `TopSpeed` (108 km/h); 0 to 30 km/h takes about 2 s at 25°;
- **Ground Friction** (`CarveGrip`) turns the velocity toward the skis: carving;
- with no pull, **Braking Deceleration** (`UpdateGlide`, every machine) is the snow friction alone when you glide
  along your skis, plus `SkidBraking` / `SkidFriction` the more the skis are sideways to your motion: a skid.

Gotcha for Creators (it caused floating trees and mismatched paintball spreads here): a random node is **pure**, so
every wire from it draws a new number. Draw once into a variable (Set), then read the variable.

`LeanIntoTurn` (every machine) rolls the body into turns and lays the skis flat on the snow.

Gotcha for Creators: Other5's Speed stat sets Max Walk Speed from the **class default** whenever it changes, so the
movement component's defaults in `BP_SkiCharacter` match the tuning (set by `Docs/Scripts/SetupDefaults.py`).

Gotcha for Creators: don't override **BeginPlay** in a child of an Other5 character without a call to the parent's
(right-click the event > Add Call to Parent Function). The parent adds the Esc/F10 game menu keys
(`IMC_BaseGamePawn`), checks the saved admin PIN and refreshes player names; skipping it left SKIvSKI without a game
menu. The graph DSL can't make that call, so SKIvSKI has no BeginPlay: it sets up from its first Tick
(`SkiBeginPlay`).

### The slope (BP_SkiSlope, `Docs/Graphs/BP_SkiSlope.lisp`)

Place it at the origin, unrotated: X runs downhill. `HeightAt(X, Y)` is the whole shape: the lobby (flat, X < 0),
the run falling at the difficulty's angle and flattening out over the last 15% (the finish run-out), banks where it
narrows from `TopWidth` to `FinishWidth`, a ridge between the two start gates that fades out by 45% of the way down
(so the teams start apart and meet), and moguls plus long rollers from sines with random phases.

`Generate` builds a Procedural Mesh grid (`CellSize`) with collision from `HeightAt`, plants pines (two instanced
meshes: a cone and a cylinder) at random except on each team's racing line (`ClearPathWidth`), and moves the gates and
finish arch onto the snow. Difficulty (`SlopeDegreesByLevel`, `BumpHeightByLevel`, `TreeCountByLevel`, each Easy /
Medium / Hard) and everything random come from `Seed`.

**Multiplayer:** only `Seed`, `Difficulty` and `BuildId` replicate. The server calls `Rebuild`; `BuildId`'s RepNotify
runs `Generate` on every machine, which all build the same slope. The lobby is always flat, so nobody falls while it
rebuilds between rounds.

### Paintballs (`Docs/Graphs/BP_SkiCharacter.Paint.lisp`, `BP_Paintball.lisp`)

A gun is a data asset: mesh, muzzle offset, `MuzzleSpeed`, `BallGravityScale`, `BallSize`, `ShotsPerSecond`,
`PelletsPerShot`, `SpreadDegrees`, `FireSounds` (one is picked at random per shot), `FireMontage`, and for the store
`Price`, `Blurb`, `MagSize`, `ReloadSeconds`, `bFullAuto` and `ReloadMontage` (see the store's table above). Add a
gun by copying a `DA_Paint*` and adding it to the character's `Guns` (the store's list; the first is everyone's).

**Ammo** is counted on the player's own machine: each shot takes one from the magazine (`Ammo`, sized by
`MagSizeFor`: the gun's `MagSize` times the hopper); R, or the last ball out, reloads from the spare paint (`Spare`,
`SpareMax`) while there's any (`ReloadSeconds`, with Other5Combat's reload montage for the kind of gun, on the `UpperBody` slot). A
semi-automatic gun fires once per click, a full-automatic one while the trigger is held; both at most `ShotsPerSecond`.

The guns are Other5Combat's meshes in the `weapon_r` hand socket. Their barrels point along the mesh's +Y, so the
character turns the gun -90 degrees (yaw) after attaching it, as Other5Combat's weapons do with their Attach Offset,
and the muzzle offsets are along Y. The static meshes are centred on their middle, but Other5Combat holds skeletal
meshes whose pivot is the grip, so each gun has a `GripOffset` (worked out by `SetupGuns.py` from the two meshes)
that `ShowGun` puts it at. Each gun's `ArmsKind` (0 pistol, 1 rifle, 2 shotgun) picks how the upper body holds it. Every gun fires with Other5Combat's rifle shots for now (a suppressed,
paintball-like pop) and plays Other5Combat's fire montage for its kind of gun (pistol, rifle, shotgun): additive
recoil in the anim graph's `FullBodyAdditivePreAim` slot. `SpawnBalls` runs on every machine for every shot, so the
sound and the recoil happen there.

A ball is a sphere (the root, so Projectile Movement sweeps it) flying with gravity; it keeps the skier's own speed.
On the snow, a tree or an arch it leaves a splat decal in the team colour and goes.

**Multiplayer (the pattern):** balls are not replicated actors. The shooter's machine spawns its own balls at once
(`TryFire` → `SpawnBalls`) and sends `ServerFire(muzzle, direction, seed)`. The server spawns the same balls (only
these score) and sends `MulticastFire`, so every other machine spawns them too. The seed makes a spread shot's pellets
go the same way everywhere.

**Hitting a skier:** only the server's copy counts. It calls the skier's `PaintedBy`, which asks the director
(`ResolvePaintHit`: 0 doesn't count, 1 hit and out, 2 bounce, rolled against the shooter's `BounceChance`), then
`MulticastPaintResult` (Multicast, Reliable) shows it on every machine: a splat stuck to the skier and "Hit!", or a
ricochet ball (`MirrorVectorByNormal`) and "Bounce!". The other machines' copies of the ball just vanish on a skier,
so nobody sees a splat that turns out to be a bounce. Everyone hears it too (`S_SkiHit` / `S_SkiBounce`). The pop-ups are
the HUD's `AddPopup` / `DrawPopups`: projected to the screen each frame (`Project`) on the skier who was hit (`Target`;
at 20 m/s a word left at the spot of the hit was behind everyone within a second); the word starts nearly twice its
size and settles, flies up the screen (fast, then slowing) and fades over `PopupSeconds`, centred, a little lighter
than the team colour and outlined in black. "Hit!" is big (Size 1), "Bounce!" smaller (0.6).

A Blueprint lesson from this (fixed 2026-11-15): `ResolvePaintHit`'s casts used to sit inside the function itself. A
Cast's Then/Cast Failed outputs end that line of the graph, so the Return node was only wired from "not racing", and a
function that runs out without reaching its Return node gives its outputs' defaults: every real hit scored and put the
skier out (replicated state) but returned 0, so `PaintedBy` never sent `MulticastPaintResult` (no "Hit!", splat or hit
sound anywhere). The casts now live in `JudgePaintHit`, which leaves its answer in `HitResult`, and `ResolvePaintHit`
always reaches its Return. Whenever a function returns a value, make sure every path ends on a Return node.

Balls ignore WorldDynamic objects (so a spread shot's pellets don't hit each other), so anything they should splat on
must be WorldStatic (BlockAll): the slope's snow, trees and arches are.

### Rounds and teams (`Docs/Graphs/BP_SkiDirector.lisp`)

The director is a Game Coordinator child: `On Player Pawn Changed` places a new character, and four times a second
`ServerStep` moves the round on (phases 0 Lobby, 1 Countdown, 2 Race, 3 Results). Teams come from Other5 (new players
join the smaller team; T calls **Request Team**, allowed only while the director has switching on: the lobby). It
moves skiers with the character's `PlaceAt` (teleport, stop, and a RepNotify that turns the owning player's skis and
camera), freezes them for the countdown (`bSkiFrozen`), resets outs, hits and team scores (`ResetRound`) at the
countdown, checks who crossed the finish (`IsPastFinish`) or got lost (`IsOutOfBounds`: back to the gate, or the lobby),
ends the race when everyone has finished or is out, and adds points (team score with **Add Team Score**, coins with
the character's `AddCoins`, Other5's inventory currency). It replicates the phase, when it ends (server time), the
difficulty and a message for the HUD.

The server-only parts check the player's **Has Valid Admin PIN** (Other5's player state) for difficulty changes.

### Pings and character select

Both are Other5's, for every Creation. Pings and quick chat work as in CubeEscape: middle mouse pings the spot under
the crosshair (hold it for the quick-chat wheel), with markers, the chat line and sound (Other5Comms, keys in
Settings > Controls). Character select is Other5's "Choose your fighter" screen: the skier has an **Other5 Character
Skins** component (Manny, Quinn, the Countess, from Other5Characters) with **Choose On Join** (a player who hasn't picked
a fighter picks one when they join) and **Menu Button** (a Fighter button in the game menu) ticked.

### The slope's trees and run-out

Pines are never closer than **TreeGap** (2.5 m, longer than the skis) of open snow, crown to crown, so nobody can be
wedged between two of them (`PlantTree` checks every pine already planted). Past the finish the snow goes on for
**RunoutLength** (150 m): flat where the run ends, rolling gently (under a degree), then curving up to **RunoutRise**
(45 m) at its end, enough height to stop a skier at top speed, so everyone stays on the snow.

### The winter look (optional art) and the valley

Around the slope the snow carries on as hills (`OuterHeightAt`): rising away on every side for **OuterWidth** (600 m)
and curving up into a ridge at the rim, so the slope sits in a closed valley. It's the same mesh as the run, its cells
widening outwards (`OuterSteps`), so there's no seam. **ForestCount** pines stand on the hills just out of bounds.

The good-looking art (snowy pines, a snow material, snow clumps, rocks, distant pine cards, falling snow; optionally **MountainCount** rings of mountains
**MountainDistance** away, off by default: the pack's mountain mesh is a whole ring of peaks that leaves thin slivers in the sky
at this size) comes from **Other5WinterBiome**, a *private* plugin: it's made from paid Fab
packs, whose licence allows shipping them cooked in a creation but not sharing the source files, and SKIvSKI is public.
So SKIvSKI never references those assets: it names them by path in the **Slope|Look** variables (`LookTree`,
`LookSnow`, ...), and `ApplyLook` loads them at run time (**Load Asset Blocking**). When they load, `bFancy` is set:
the cones and trunks are hidden (skiers still hit them, so the gameplay is the same) and the art is placed. When they
don't (a project without the plugin), the slope keeps its own look: cones on trunks and plain snow.

- **Cooking:** `SKIvSKI.uplugin` lists Other5WinterBiome as an *optional* plugin. The Other5 Tool ticks a creation's
  optional plugins when they're in the project, so a cook with the plugin carries its paks; without it, the creation
  cooks and plays with the cones.
- Everything random still comes from `Seed`, and the scenery draws from the stream after the run's own pines, so the
  run is the same with or without the art.
### The HUD (`Docs/Graphs/BP_SkiHUD.lisp`)

All Blueprint, drawn on the HUD's canvas each frame (`Event Receive Draw HUD`: **Draw Rect** and **Draw Text**) in
Other5's UI style: dark see-through panels with a coloured top edge, Orbitron (`/Game/UI/Fonts/Font_Orbitron`) for
titles and numbers and Exo 2 for the rest, Other5's colours (`Ink`, `Muted`, `Neon`, `Gold`, `Bad`, as linear colours).
Every size is for a 1080-pixel-high screen times `U` (screen height / 1080), and text is centred with **Get Text
Size**, so it fits any resolution.

- Top: the round panel (LOBBY / GET READY / RACE / RESULTS, the time, the slope) between the two team score boxes,
  which glow in the team's colour for half a second when the score goes up.
- Middle: the countdown seconds (each pops in big and settles), GO!, and at the results a scoreboard: the winner and
  score, then every player (Red, then Blue) with points, outs and place.
- Bottom: your speed, team, OUT and outs on the left; your gun, paint bounce chance, ski friction and coins on the
  right; the keys in the lobby.
- Sounds (`PlayRoundSounds`, this machine only, from what the director replicates): a beep each countdown second, a
  higher one at GO!, a chime when a team scores, a fanfare with the results.

### Animation (`Animation/ABP_Skier`)

Legs: on the skis, side by side, toes along them. Every mannequin pose stands staggered with the feet turned out (even
`MM_Idle`), so the legs are placed rather than played: `MM_Idle` in component space, the pelvis lowered 5 cm and, as you
crouch, up to 34 cm more and 10 cm back (`SkiCrouch`: 0.35 standing still, 1 from about 94 km/h, so the knees bend more
the faster you go), **Two Bone IK** puts each foot on its ski with the knee
aimed forward, and **Transform (Modify) Bone** turns each foot to point along its ski. Upper body: the rifle
pose and aim offset of the gun in hand: pistol (`MM_Pistol_Idle_ADS`, `AO_MM_Pistol_Idle_ADS`), rifle (`MM_Rifle_Idle_Hipfire`,
`AO_MM_Rifle_Idle_Hipfire`) or shotgun (`MM_Shotgun_Idle_Hipfire` with the rifle's aim offset), picked by two Blend Poses by
Bool (`bArmsPistol`, `bArmsShotgun`, from the gun's `ArmsKind`), then the `FullBodyAdditivePreAim` montage slot (the guns'
fire recoil) and the `UpperBody` slot (their reloads). The aim offsets use `AimYaw`, `AimPitch` (where the player aims relative to the skis). A
Layered Blend per Bone joins them from `spine_01` up (mesh-space rotation; without that branch filter the whole body
plays the legs' idle and the upper body freezes, as happened in SKIvSKI 1.18-1.21). Then the spine leans forward with the
crouch (`spine_01` to `spine_03`, 8 degrees each at full crouch about the mesh's sideways axis, Alpha `SkiCrouch`), and the
event graph adds that lean (`LeanDegrees` x `SkiCrouch` x cos `AimYaw`) to `AimPitch`, so the aim offset lifts the arms and
gun back to where the player aims (`DebugAimAt` and `DebugGunAim` measure it).
No walking legs: on skis the feet stay put. How to build it yourself in the editor: `Docs/SkiStanceAnimation.md`.
The Anim Graph is built by `Docs/Scripts/BuildAnimGraph.ps1`; the event graph is `Docs/Graphs/ABP_Skier.lisp`.
With a retargeted skin (Countess, Gideon) `FitToSkin` moves the gun and helmet onto the shown skin's hand and head.

## Tuning

Everything is a variable with a category, so it can be changed in a Blueprint's Class Defaults (or per instance in
the level):

- `BP_SkiCharacter` **Ski|Tuning**: Gravity, SnowFriction, TopSpeed, FullInputAccel, TurnRate, CarveGrip, SkidBraking,
  SkidFriction, SkateInput, SkateSpeed, EdgeGrip, AcrossHoldSeconds, MaxLean. (Keep the Character Movement defaults in step: see the gotcha.)
- `BP_SkiSlope` **Slope|Layout** and **Slope|Difficulty**.
- `BP_SkiDirector` **Round|Settings**: LobbySeconds, CountdownSeconds, RaceSeconds, ResultsSeconds, HitPoints,
  FinishPoints, MinPlayers, HitCoins, SurviveCoins.
- `BP_SkiPlayerState` **Gear** (each player's starting gear): SnowFriction 0.02, BounceChance 0.10.
- The store: `BP_SkiCharacter` **Store** (Skis, Waxes) and **Paint** (Guns): what it sells, in order; their prices and
  numbers in the `DA_*` assets (`SetupGuns.py`, `SetupGear.py`).
- `BP_SkiGameMode` **Other5|Teams**: the team names and colours, auto-balance, switching, friendly fire.
- `BP_SkiHUD` **Popups**: PopupSeconds.
- The guns: `Guns/DA_Paint*`.

## How the assets were made (and how to rebuild them)

The Blueprints were written as text and built over **Unreal MCP** (Epic's editor plugin, enabled in Other5):

- `Docs/Graphs/*.lisp`: every graph in the Blueprint graph DSL (`BlueprintTools.write_graph_dsl`), with comments.
  These are the readable source of the logic.
- `Docs/Scripts/*.py`: editor Python for assets, components and defaults (`SetupInput`, `SetupMaterials`,
  `SetupBlueprints`, `SetupGuns`, `SetupAnimation`, `SetupDefaults`, `SetupSkiMap`, `SetupTestMap`,
  `SetupCreationLabel`).
- `Docs/Scripts/UnrealMcp.ps1`: a PowerShell Unreal MCP client with the helpers; `BuildAll.ps1` rebuilds everything
  in order (editor open, MCP running); `BuildAnimGraph.ps1` the Anim Graph. If another project's editor already holds
  Unreal MCP's port 8000, start Other5's editor on another port (see the top of `UnrealMcp.ps1`) and set
  `$env:UNREAL_MCP_URL`.
- `Docs/Scripts/LayoutGraphs.py`: makes the generated graphs readable (the DSL puts every node in one row). Per event
  or function, the execution chain runs left to right in the order it runs; each data node sits just left of and below
  the node that first uses it, its own inputs further left, so wires stay short; a node's other exec outputs (Branch
  False, Cast Failed, loop Completed) start rows below; the events are stacked, each in a **comment box holding its
  comment from the .lisp file**. Graphs with no exec pins (the Anim Graph) use the editor toolset's own layered
  layout (`BlueprintTools.arrange_nodes`). It runs last in `BuildAll.ps1`; run it alone after any graph change:
  `py "Docs/Scripts/LayoutGraphs.py"` in the editor's console box.
- `Docs/Scripts/SetupAudio.py`: synthesises the game's sounds (no recordings, nothing to license) and imports them.
What the DSL can't do, done through the Blueprint editor's UI by `BuildAll.ps1`: inputs on custom events and their
**Replicates** setting (Run on Server / Multicast, Reliable). If you edit the Blueprints by hand, the `.lisp` files
go stale: either keep editing by hand, or update the text and run `BuildAll.ps1`.

## Tests

The Other5 test runner (`-Other5TestScript=`) drives the scripts in `Docs/Tests`:

- `SkiRamp.txt` on `L_SkiTest`: gravity alone, carving, S to stop and then slide backwards, W back downhill.
- `SkiSlope.txt`, `SkiGate.txt` on `L_SkiVSki`: riding the generated slope.
- `SkiRound.txt`: lobby, paintballs, team switch, countdown at the gate, race (one player).
- `SkiLook.txt`: screenshots of the ski stance and aiming.
- `SkiPolish.txt`: the HUD in every phase (moved on with `DebugPhase`), the gun in hand, recoil and the pop-ups.
- `SkiFeatures.txt`: character select, a middle-mouse ping, each gun held, the game menu's Fighter button, the run-out.
- `SkiStore.txt`: the store (B), buying with `DebugBuy` (enough coins, too few, free, owned), ammo and the reload
  (`DebugEmpty`), and a race's coins with the store opening at the results. Each `DebugScore` logs coins, gun, ammo,
  skis and friction; the server logs every request (`SKI| buy <kind x 100 + index> price coins phase`). Tested
  2026-11-16 standalone; a listen-server host and a client: the client's `ServerBuy` reached the server.
- A hit over the network: a listen-server host runs `call pawn DebugHitMe` (a real `MulticastPaintResult`) while a client
  screenshots it. (Editor Python can't test RPCs: its calls run them locally.) `DebugHitMe` skips the director, so it
  can't catch a scoring bug: for a real paintball hit, run a dedicated server (`-server -SkiPracticeHits`) with
  `SkiRealHitServer.txt` (a 120 s lobby), then client A with `SkiRealHitA.txt` (presses `]` so the lobby restarts at
  that length, then aims and fires) and client B with `SkiRealHitB.txt` (screenshots `RealB###` every 0.25 s); the
  server logs `SKI| paint result 1` and both clients' shots show "Hit!" over B.
- `Run-SkiMultiplayer.ps1`: a dedicated server and two clients (`SkiDuelA/B.txt`) aiming at each other through a
  lobby and a race (the server runs with `-SkiPracticeHits`). 2026-11-10: shared teams Red/Blue, a hit puts the other
  player out, team score and a coin for the shooter, outs reset at the countdown.

The character has `DebugReport`, `DebugScore`, `DebugAim`, `DebugFire`, `DebugPopup`, `DebugHitMe`, `DebugPhase` and `DebugSteerToMiddle` functions for these
(`call pawn DebugReport`). Mouse buttons sent by the runner's `keydown` don't reach Enhanced Input, hence `DebugFire`.

## Status

**Works (tested 2026-11-10, editor build):** ski movement and steering on the ramp and the generated slope; the slope
at three difficulties with pines, gates and finish; three paintball guns, splats, Q to switch; Other5's shared teams
(auto-balanced on join, T to switch in the lobby only); lobby, countdown, race, finish places, results and a new slope
each round; on a dedicated server with two clients: a hit puts the other player out (grey skis and helmet, can't
fire, further hits ignored), the team scores, the shooter gets a coin, and the next countdown brings everyone back in;
the HUD (team scores in team colours, outs, paint bounce %, ski friction, coins) on the plain Other5 game HUD; the
"Hit!" / "Bounce!" pop-ups rising and fading; admin difficulty keys; the ski stance and aiming upper body; PIE
(server + client) starts with no errors. Polish (2026-11-10, `SkiPolish.txt`, PIE): the gun points where the skier aims, the fire
recoil plays in the new slot, the HUD in every phase, the pop-ups, and every graph laid out with comment boxes. The
sounds play (no errors) but nobody has listened to them yet. Not seen in a test yet: a real bounce (10%: the ricochet path is built and
compiles), and the controls in Settings > Controls.

**Stubbed or rough:**
- Pines are engine cones and cylinders. The snow has no texture.
- The guns are Other5Combat's pistol, rifle and shotgun meshes, held as Other5Combat holds them (2026-11-10: they were
  turned 90 degrees before). Every gun uses the rifle's shot sounds; no muzzle flash or splash particles yet.
- The HUD is drawn on the canvas (Draw Rect / Draw Text), not a UMG widget, so it has no hover or click; fine for a
  read-only HUD.
- The store (2026-11-16): ammo is counted on the player's own machine (no cheat protection), and only the shooter sees
  their reload animation. The store needs a mouse (no gamepad navigation yet). Better paint (bounce chance, colours)
  isn't sold yet.
- Finish and out-of-bounds are polled four times a second. Players stuck across the slope in a bowl must steer out.
- No lag compensation: the server's ball starts from the shooter's muzzle when the RPC arrives.
- No bots. Not tried on Mac, nor as a cooked creation pak (PAL_SKIvSKI is set up but nothing has been cooked).

**Next / TODO:**
- **Store**, more to come: better paint (lower bounce chance, colours and other effects); gamepad navigation.
- **Ski compass** (Matt 2026-11-10, later): a compass-like HUD element showing which way your skis point relative to
  the fall line (straight downhill), like Other5Compass but for the hill.
- A muzzle/splash effect (Niagara); each gun its own shot sound; nicer pines (Megascans are fine to use,
  Matt 2026-11-10); a ski-specific idle/turn pose set (or Control Rig leg IK); a cooked-pak test on a server.
- **Creator guides** on other5.xyz: very detailed, lots of pictures and step-by-step how-tos, the animation work above
  all (Matt 2026-11-10). Topics in `CreatorTopics.md`.

## Decisions (Matt, 2026-11-10)

Megascans/Fab assets are fine (Other5ForestBiome already uses them); chunk 1021; the repo stays public (a downloadable
zip to learn from); teams are a shared C++ Other5 system (done, Other5 branch `SkiVSki`); a hit puts you out with a
bounce chance; the Speed stat raising ski speed is good; ski friction and paint are shop items between runs.
