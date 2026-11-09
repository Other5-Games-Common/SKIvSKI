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

### Scoring

- Each paintball hit on the **other** team during the race: **1 point** (`HitPoints`) for the shooter's team.
- Crossing the finish: **10, 8, 6, 5, 4, 3, 2, 1** points (`FinishPoints`) for 1st, 2nd... to your team.
- Most points wins the round. Paint doesn't hurt (no health loss, no deaths): this is a race.

## How it works

Everything is in `Content/` (Blueprints, data, materials, one level). C++: none; Other5 gives the base classes.

| Piece | What it is |
|---|---|
| `Blueprints/BP_SkiCharacter` | The skier: a child of Other5Combat's `BP_Other5ProjectileCharacter` (camera, health, skins, game menu) with skis, a team-coloured helmet and a paintball gun. Movement, firing, team colours. |
| `Blueprints/BP_SkiSlope` | The random slope: builds snow, pines, start gates and the finish from `Seed` + `Difficulty`. |
| `Blueprints/BP_SkiDirector` | Rounds and teams: a child of Other5's **Game Coordinator** (`AOther5GameCoordinator`), placed once in the level. |
| `Blueprints/BP_SkiPlayerState` | Each player's team, hits, points, finish place (child of `Other5BasePlayerStateGAS`). |
| `Blueprints/BP_Paintball` | One paintball. |
| `Guns/BP_PaintGunData`, `Guns/DA_Paint*` | Gun data: a Blueprint Primary Data Asset class and the three guns. |
| `Blueprints/BP_SkiHUD` | Round, scores, gun and speed as text (child of Other5Combat's HUD). |
| `Blueprints/BP_SkiGameMode` | Pawn, player state, controller and HUD classes (child of `Other5GameModeBase`). |
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
   line), less snow friction (`SnowFriction` × `Gravity` × cos(slope)). That becomes **Add Movement Input** along
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
On a hit it leaves a splat decal in the team colour (stuck to a skier if it hit one) and goes.

**Multiplayer (the pattern):** balls are not replicated actors. The shooter's machine spawns its own balls at once
(`TryFire` → `SpawnBalls`) and sends `ServerFire(muzzle, direction, seed)`. The server spawns the same balls (only
these score) and sends `MulticastFire`, so every other machine spawns them too. The seed makes a spread shot's pellets
go the same way everywhere. A scoring ball that hits a skier calls `PaintedBy` on the server, which asks the director.

Balls ignore WorldDynamic objects (so a spread shot's pellets don't hit each other), so anything they should splat on
must be WorldStatic (BlockAll): the slope's snow, trees and arches are.

### Rounds and teams (`Docs/Graphs/BP_SkiDirector.lisp`)

The director is a Game Coordinator child: `On Player Joined` puts a new player on the smaller team, `On Player Pawn
Changed` places a new character, and four times a second `ServerStep` moves the round on (phases 0 Lobby, 1 Countdown,
2 Race, 3 Results). It moves skiers with the character's `PlaceAt` (teleport, stop, and a RepNotify that turns the
owning player's skis and camera), freezes them for the countdown (`bSkiFrozen`), checks who crossed the finish
(`IsPastFinish`) or got lost (`IsOutOfBounds`: back to the gate, or the lobby), and keeps the scores. It replicates the
phase, when it ends (server time), both scores, the difficulty and a message for the HUD.

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
  FinishPoints, MinPlayers.
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
  lobby and a race. 2026-11-09: teams Red/Blue, rounds, replicated paintballs, server-counted hits, scores on both
  clients (Red 5 - Blue 6).

The character has `DebugReport`, `DebugScore`, `DebugAim`, `DebugFire` and `DebugSteerToMiddle` functions for these
(`call pawn DebugReport`). Mouse buttons sent by the runner's `keydown` don't reach Enhanced Input, hence `DebugFire`.

## Status

**Works (tested 2026-11-09, editor build):** ski movement and steering on the ramp and the generated slope; the slope
at three difficulties with pines, gates and finish; three paintball guns, splats, Q to switch; teams (auto-balanced,
T to switch), lobby, countdown, race, finish places, results and a new slope each round; server-scored hits and
replicated scores on a dedicated server with two clients; admin difficulty keys; the HUD; the ski stance and aiming
upper body. Not checked yet: the controls showing in Settings > Controls (they use Add Other5 Mapping Context, as
the docs say), and PIE.

**Stubbed or rough:**
- Pines are engine cones and cylinders (see the open questions). The snow has no texture.
- The guns are Other5Combat's pistol, rifle and shotgun meshes, roughly in the hand (no muzzle socket; the balls still
  go where the crosshair points). No firing sound or muzzle flash yet; no splash particles.
- The HUD is Draw Text, not a widget. Other5Combat's grenade and health-pack counters still show (unused here).
- Finish and out-of-bounds are polled four times a second. Players stuck across the slope in a bowl must steer out.
- No lag compensation: the server's ball starts from the shooter's muzzle when the RPC arrives.
- With `-SkiPracticeHits`, lobby points carry into the race's score.
- No bots. Not tried on Mac, nor as a cooked creation pak (PAL_SKIvSKI is set up but nothing has been cooked).

**Next:** sounds and a muzzle/splash effect (Niagara); a UMG HUD with a results table; nicer pines; a ski-specific
idle/turn pose set (or Control Rig leg IK for knees over uneven snow); a cooked-pak test on a server; Creator guides.

## Open questions for Matt

1. **Pines from Fab/Megascans:** using them needs your sign-in and accepting their licence (not done). Also, this repo
   is **public**, and the Fab licence doesn't allow redistributing source assets, so licensed trees would need a
   private plugin (like CubeEscape's packs) or to come from a public-domain source. The cones are a placeholder.
2. **Chunk 1021** for `PAL_SKIvSKI` (next free after Characters 1019 / Creatures 1020): OK?
3. **Public repo:** fine for SKIvSKI to stay public (CubeEscape is private)? Its only branch is `SkiVSki` (GitHub made
   it the default); a `main` appears when you merge.
4. **Teams as an Other5 system:** this Creation does teams in Blueprints. A reusable proposal is in Other5
   `Docs/Teams.md` (branch `SkiVSki`): want it in C++ for all Creations, or keep it in Blueprints for now?
5. **Scoring and paint:** 1 point a hit plus 10/8/6... for finishing, and paint doesn't hurt or slow you. Change
   anything (e.g. a hit slows the skier, or Combat's GAS damage)?
6. **Other5's Speed stat** also raises the ski top speed (fighter progression). Keep it?
7. **Creator guides:** how detailed should the website guides be (ski movement, projectile guns, teams/rounds, random
   terrain)? They're listed in `CreatorTopics.md`.
