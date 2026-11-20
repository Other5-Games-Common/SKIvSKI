# Ski runs (BP_SkiRunData)

SKIvSKI has several runs. Each is a data asset of the Blueprint class `Runs/BP_SkiRunData`, so a new run needs no
graph work: copy a `DA_Run*` asset, change its numbers and add it to the slope's **Runs** list. The slope
(`BP_SkiSlope`) still builds the snow, pines, gates and forts from a seed on every machine; a run only tells it what
to build. Rebuild the four that ship with `Docs/Scripts/SetupRuns.py`.

| Run | Length | What it's like | Forts | Sky |
|---|---|---|---|---|
| Pine Bowl (`DA_RunPineBowl`) | 400 m | The original run. | 3 | Clear day |
| Long Glacier (`DA_RunLongGlacier`) | 800 m (2x) | Gentler and smoother, wider at the finish. | 5 | Golden hour |
| Storm Chute (`DA_RunStormChute`) | 600 m | Narrow, steep and bumpy. | 4, zigzagging | Snowstorm |
| Grand Descent (`DA_RunGrandDescent`) | 1.2 km (3x) | Wide, long, a fort in the middle. | 7 | Overcast, light snow |

## What a run sets

A value left at **0** keeps the slope's own (its Slope|Layout value in Class Defaults).

| Value | What it does |
|---|---|
| **Run Name**, **Blurb** | Shown on the HUD's round panel ("Long Glacier - medium") and for your own UI. |
| **Length** | Start gates to the bottom, in cm (40000 = 400 m). The finish arch is at 90%, the last 15% flattens out. |
| **Top Width**, **Finish Width** | How wide the run is at the top and at the finish, in cm. |
| **Slope Scale** | Times the difficulty's angle (13°, 19°, 26° for easy, medium, hard). 0.85 on a long run keeps it from getting too fast. |
| **Bump Scale** | Times the difficulty's moguls and rollers. |
| **Shape Seed** | The hills' shape. Any number above 0 gives the run the same moguls and rollers every time; 0 makes new ones each round. |
| **Cell Size** | The snow mesh's grid, in cm. Leave 0 (2.5 m) unless a very long run builds slowly; 300 is fine for 1.2 km. |
| **Tree Scale** | How wooded: the pines per 100 m are the same as on a 400 m run (Tree Count Length), times this. Their placement is random each round, by the usual rules (Tree Gap between crowns, clear racing lines, clear round forts). |
| **Fort Spots** | Where the forts stand, the same every time. Each is X: how far down (0 the gates, 1 the bottom) and Y: across (-1 the left edge, 0 the middle, 1 the right edge). |
| **Fort Count**, **Fort Seed**, **Fort From**, **Fort To** | Only when Fort Spots is empty: that many forts, spaced evenly from Fort From to Fort To of the way down, on alternating sides. A Fort Seed above 0 places them the same every time; 0, differently each round. |
| **Race Seconds** | How long the race may last (a long run takes longer). 0 keeps the director's. |
| **Sky** | An **Other5 Sky Preset** (Other5's own system, for any creation: `Runs/Skies/DA_Sky*`, and Other5 `Docs/SkyPresets.md`): the sun, light, fog, clouds and weather. Between rounds the sky eases to the next run's over the slope's **Sky Blend Seconds**. With no sky the level keeps its own, and the winter look's own snowfall. |

Keep forts at least 25 m apart down the run: the snow under a fort is flattened for the two forts nearest each 10 m
stretch (`FortLookup`), so a third one close by would sit on bumps.

## How they take turns

- The slope's **Runs** (Slope|Runs) are the runs in order. The director (`BP_SkiDirector`) uses the next one after
  each round's results, **Rounds Per Run** rounds each (0: stay on one).
- An admin can switch runs in the lobby or the results with **,** and **.** (the slope keeps its difficulty, still on
  **[** and **]**). Without an AdminPIN on the server everyone is an admin.
- A server can start on one: `-SkiRun=2` (the second in the list) or `-SkiRun=Glacier` (the start of its name).

## Multiplayer

The server sets the slope's **Run** (replicated) and calls Rebuild, as it always has with the seed and difficulty.
Every machine then builds the same run (`ApplyRun` copies the run into the slope's values, then `Generate`) and shows
its sky. Run data assets are content, so they replicate as references: nothing else to set up.

## Make a new run

1. Duplicate `Runs/DA_RunPineBowl` and rename it (`DA_Run<Name>`).
2. Open it and set Run Name, Length, widths, scales, a Shape Seed and its Fort Spots. Pick a Sky (or make one: duplicate
   a `Runs/Skies/DA_Sky*`).
3. Open `Blueprints/BP_SkiSlope` > Class Defaults > Slope|Runs > **Runs**, add it.
4. Play: press **.** in the lobby until it's up, or start the server with `-SkiRun=<Name>`.
