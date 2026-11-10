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
| Left mouse (right trigger) | Fire. Hold for the gun's rate. |
| Q (Y) | Next paintball gun. |
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
- **Coins:** every point you earn is also a coin (`CoinsPerPoint`), kept between rounds, for the shop.
- Your gear (on your player state, shown on the HUD): **paint bounce chance** and **ski friction** (the snow friction
  of your skis; wax will lower it). The shop between runs will sell better ones.
- Paint doesn't hurt (no health loss, no deaths): this is a race.

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
| `Blueprints/BP_SkiPlayerState` | Each player's outs scored (`Hits`), points, finish place, whether they're out (`bOut`), and gear: `SnowFriction`, `BounceChance` (child of `Other5BasePlayerStateGAS`, whose `TeamId` is the team). |
| `Blueprints/BP_Paintball` | One paintball. |
| `Guns/BP_PaintGunData`, `Guns/DA_Paint*` | Gun data: a Blueprint Primary Data Asset class and the three guns. |
| `Blueprints/BP_SkiHUD` | Round, team scores, your state and gear, coins, and the "Hit!" / "Bounce!" pop-ups, as text (child of Other5's game HUD `BP_Other5GameHUD`: menu and chat, none of Combat's ammo, grenade, health or credits widgets). |
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
3. **Lets gravity pull** (`PushDownSlope`): pull along the skis = `Gravity` × sin(slope) × cos(angle to the fall
   line), less snow friction (the player's `SnowFriction` gear × `Gravity` × cos(slope); `GetSnowFriction`). That becomes **Add Movement Input** along
   the skis (backwards when they point uphill), scaled by `FullInputAccel`.

Character Movement does the rest, and because only Add Movement Input drives it, its client prediction and server
correction work as for walking:

- acceleration = Max Acceleration × input, and the speed tops out at Max Walk Speed × input (`TopSpeed`), so a
  steeper slope, or skis nearer the fall line, go faster (about 40 / 65 / 95 km/h straight down Easy / Medium / Hard);
- **Ground Friction** (`CarveGrip`) turns the velocity toward the skis: carving;
- when the pull is weaker than the speed you have (skis turned across), **Braking Deceleration** (`SkidBraking`,
  `SkidFriction`) slows you: a skid. No pull at all brakes you to a stop.

`LeanIntoTurn` (every machine) rolls the body into turns and lays the skis flat on the snow.

Gotcha for Creators: Other5's Speed stat sets Max Walk Speed from the **class default** whenever it changes, so the
movement component's defaults in `BP_SkiCharacter` match the tuning (set by `Docs/Scripts/SetupDefaults.py`).

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
`PelletsPerShot`, `SpreadDegrees`. Splat Pistol: fast, flat, 6 a second. Big Marker: big slow loopy balls. Splatter
Gun: six balls in a cone. Add a gun by copying a `DA_Paint*` and adding it to the character's `Guns`.

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
so nobody sees a splat that turns out to be a bounce. The pop-ups are the HUD's `AddPopup` / `DrawPopups`: a world
spot projected to the screen each frame (`Project`), rising and fading over `PopupSeconds`.

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

### Animation (`Animation/ABP_Skier`)

Legs: a Two Way Blend from a standing to a crouched pose (`SkiCrouch`: deeper the faster you go). Upper body: the rifle
hip-fire pose through an aim offset (`AimYaw`, `AimPitch` from where the player aims relative to the skis). A
Layered Blend per Bone joins them from `spine_01` up (mesh-space rotation). No walking legs: on skis the feet stay put.
The Anim Graph is built by `Docs/Scripts/BuildAnimGraph.ps1`; the event graph is `Docs/Graphs/ABP_Skier.lisp`.

## Tuning

Everything is a variable with a category, so it can be changed in a Blueprint's Class Defaults (or per instance in
the level):

- `BP_SkiCharacter` **Ski|Tuning**: Gravity, SnowFriction, TopSpeed, FullInputAccel, TurnRate, CarveGrip, SkidBraking,
  SkidFriction, SkateInput, AcrossHoldSeconds, MaxLean. (Keep the Character Movement defaults in step: see the gotcha.)
- `BP_SkiSlope` **Slope|Layout** and **Slope|Difficulty**.
- `BP_SkiDirector` **Round|Settings**: LobbySeconds, CountdownSeconds, RaceSeconds, ResultsSeconds, HitPoints,
  FinishPoints, MinPlayers, CoinsPerPoint.
- `BP_SkiPlayerState` **Gear** (each player's starting gear): SnowFriction 0.05, BounceChance 0.10.
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
  in order (editor open, MCP running); `BuildAnimGraph.ps1` the Anim Graph.

What the DSL can't do, done through the Blueprint editor's UI by `BuildAll.ps1`: inputs on custom events and their
**Replicates** setting (Run on Server / Multicast, Reliable). If you edit the Blueprints by hand, the `.lisp` files
go stale: either keep editing by hand, or update the text and run `BuildAll.ps1`.

## Tests

The Other5 test runner (`-Other5TestScript=`) drives the scripts in `Docs/Tests`:

- `SkiRamp.txt` on `L_SkiTest`: gravity alone, carving, S to stop and then slide backwards, W back downhill.
- `SkiSlope.txt`, `SkiGate.txt` on `L_SkiVSki`: riding the generated slope.
- `SkiRound.txt`: lobby, paintballs, team switch, countdown at the gate, race (one player).
- `SkiLook.txt`: screenshots of the ski stance and aiming.
- `Run-SkiMultiplayer.ps1`: a dedicated server and two clients (`SkiDuelA/B.txt`) aiming at each other through a
  lobby and a race (the server runs with `-SkiPracticeHits`). 2026-11-10: shared teams Red/Blue, a hit puts the other
  player out, team score and a coin for the shooter, outs reset at the countdown.

The character has `DebugReport`, `DebugScore`, `DebugAim`, `DebugFire`, `DebugPopup` and `DebugSteerToMiddle` functions for these
(`call pawn DebugReport`). Mouse buttons sent by the runner's `keydown` don't reach Enhanced Input, hence `DebugFire`.

## Status

**Works (tested 2026-11-10, editor build):** ski movement and steering on the ramp and the generated slope; the slope
at three difficulties with pines, gates and finish; three paintball guns, splats, Q to switch; Other5's shared teams
(auto-balanced on join, T to switch in the lobby only); lobby, countdown, race, finish places, results and a new slope
each round; on a dedicated server with two clients: a hit puts the other player out (grey skis and helmet, can't
fire, further hits ignored), the team scores, the shooter gets a coin, and the next countdown brings everyone back in;
the HUD (team scores in team colours, outs, paint bounce %, ski friction, coins) on the plain Other5 game HUD; the
"Hit!" / "Bounce!" pop-ups rising and fading; admin difficulty keys; the ski stance and aiming upper body; PIE
(server + client) starts with no errors. Not seen in a test yet: a real bounce (10%: the ricochet path is built and
compiles), and the controls in Settings > Controls.

**Stubbed or rough:**
- Pines are engine cones and cylinders. The snow has no texture.
- The guns are Other5Combat's pistol, rifle and shotgun meshes, roughly in the hand (no muzzle socket; the balls still
  go where the crosshair points). No firing sound or muzzle flash yet; no splash particles.
- The HUD is Draw Text, not a widget.
- No shop yet: gear (bounce chance, ski friction) and coins are in place for it. Better paint's looks (colours) not
  started.
- Finish and out-of-bounds are polled four times a second. Players stuck across the slope in a bowl must steer out.
- No lag compensation: the server's ball starts from the shooter's muzzle when the RPC arrives.
- No bots. Not tried on Mac, nor as a cooked creation pak (PAL_SKIvSKI is set up but nothing has been cooked).

**Next / TODO:**
- **Shop between runs** (Matt 2026-11-10): spend coins on better paint (lower bounce chance, colours and other
  effects) and ski wax (lower ski friction). Other5's `AOther5Shop` / inventory currency is the likely base.
- **Ski compass** (Matt 2026-11-10, later): a compass-like HUD element showing which way your skis point relative to
  the fall line (straight downhill), like Other5Compass but for the hill.
- Sounds and a muzzle/splash effect (Niagara); a UMG HUD with a results table; nicer pines (Megascans are fine to use,
  Matt 2026-11-10); a ski-specific idle/turn pose set (or Control Rig leg IK); a cooked-pak test on a server.
- **Creator guides** on other5.xyz: very detailed, lots of pictures and step-by-step how-tos, the animation work above
  all (Matt 2026-11-10). Topics in `CreatorTopics.md`.

## Decisions (Matt, 2026-11-10)

Megascans/Fab assets are fine (Other5ForestBiome already uses them); chunk 1021; the repo stays public (a downloadable
zip to learn from); teams are a shared C++ Other5 system (done, Other5 branch `SkiVSki`); a hit puts you out with a
bounce chance; the Speed stat raising ski speed is good; ski friction and paint are shop items between runs.
