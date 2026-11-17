# SKIvSKI: default values of the Blueprints (tuning numbers, classes). Rerunnable; run after the graphs are written
# (the variables must exist). Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupDefaults"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


eal = unreal.EditorAssetLibrary
# The optional Other5WinterBiome plugin's assets are named by path only (strings, not references), so SKIvSKI still
# opens, cooks and runs without it.
W = "/Other5WinterBiome/"


def cdo(path):
    bp = unreal.load_asset(path)
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    return bp, unreal.get_default_object(bp.generated_class())


def set_all(obj, values):
    for k, v in values.items():
        try:
            obj.set_editor_property(k, v)
        except Exception as e:
            log("  cannot set %s: %s" % (k, e))


def main():
    bp, ch = cdo("/SKIvSKI/Blueprints/BP_SkiCharacter")
    set_all(ch, {
        # Ski|Tuning (cm, seconds, degrees)
        "Gravity": 980.0,            # cm/s^2
        "SnowFriction": 0.02,        # waxed skis on packed snow (along the skis; the shop's wax lowers it)
        "TopSpeed": 3000.0,          # cm/s at full pull (108 km/h)
        "FullInputAccel": 700.0,     # cm/s^2 of gravity pull that counts as full input (and the Max Acceleration)
        "TurnRate": 110.0,           # degrees per second the skis turn
        "CarveGrip": 2.5,            # Ground Friction: how fast the velocity follows the skis
        "SkidBraking": 450.0,        # cm/s^2 lost when skidding (skis across, or turning off the fall line)
        "SkidFriction": 0.4,         # extra braking that grows with speed
        "SkateInput": 0.12,          # W on flat snow
        "AcrossHoldSeconds": 0.35,   # S pauses this long with the skis across the slope
        "MaxLean": 25.0,             # degrees the body leans into a turn
        "EdgeGrip": 0.55,           # the edges hold skis across the slope up to about 29 degrees; steeper, they side-slip
        "SkateSpeed": 600.0,        # cm/s W skates up to on flat snow (22 km/h)
        "SkiStance": 12.0,           # cm: each ski's middle either side of the skier's (SetupSkiMesh.py's STANCE)
        "BindingForward": 11.0,      # cm: the boots ahead of the capsule's middle (SetupSkiMesh.py's BINDING_FORWARD)
        "SnowProbeHalf": 55.0,       # cm: SampleSnow looks this far ahead of and behind the boots
        "SkiSettleSpeed": 12.0,      # how fast the skis tilt to the snow (VInterpTo speed)
        "ExitCooldown": 10.0,        # seconds between one Exit fort (F) and the next, per skier
        "JumpPush": 450.0,           # cm/s along the skis a jump adds when (nearly) stopped, to hop up a slope
        "JumpPushBelow": 300.0,      # ...below this speed (cm/s)
        "SkiLift": 2.5,              # cm the skis ride above the snow plane (its look shows a little above its collision)
        "SkiNormal": unreal.Vector(0.0, 0.0, 1.0),   # the skis start flat
        "SnowNormal": unreal.Vector(0.0, 0.0, 1.0),
        "TeamShown": -1,             # no team colour shown yet
        "MapShown": -2,              # nor a minimap marker: the first frame decides (UpdateMapMarker)
        "MaxAimYaw": 100.0,          # degrees the camera and shots may turn from the skis (as far as the body twists)
        "GunShown": -1,              # no gun or skis shown yet: the first frame shows the player's (UpdateGear)
        "SkisShown": -1,
        "MagShown": -1,              # nor a magazine, spare paint or phase: the first frame fills them (UpdateGear)
        "SpareShown": -1,
        "PhaseShown": -1,
        "BaseSpareMags": 3,          # spare magazines everyone carries (the gun's own size); Extended Reloads add more
    })
    # The movement component's own defaults must match the tuning: Other5's Speed stat (fighter progression) sets
    # Max Walk Speed from the class default whenever it changes, so a value set only at Begin Play doesn't last.
    cmc = ch.get_editor_property("character_movement")
    set_all(cmc, {
        "max_walk_speed": 3000.0,
        "max_acceleration": 450.0,
        "ground_friction": 2.5,
        "braking_deceleration_walking": 450.0,
        "use_separate_braking_friction": True,
        "braking_friction": 0.4,
    })
    # The ski animation (legs in a ski stance, upper body aiming), instead of Other5's walking/running one.
    if eal.does_asset_exist("/SKIvSKI/Animation/ABP_Skier"):
        ch.get_editor_property("mesh").set_editor_property("anim_class", unreal.load_asset("/SKIvSKI/Animation/ABP_Skier").generated_class())
    eal.save_loaded_asset(bp, False)
    log("character defaults, max walk speed %.0f" % cmc.get_editor_property("max_walk_speed"))

    bp, sl = cdo("/SKIvSKI/Blueprints/BP_SkiSlope")
    set_all(sl, {
        # Slope|Layout (cm)
        "Length": 40000.0,          # 400 m from the start gates to the bottom
        "FortCount": 3,             # log forts down the second half of the run (BP_SkiFort)
        "FortClear": 4.5,           # pines keep as far from a fort as from a pine this big (about 5.4 m more)
        "FortCalmDistance": 1100.0, # the bumps are flat under a fort and back in full this far from its middle
        "TopWidth": 12000.0,        # the run is 120 m wide at the top...
        "FinishWidth": 4000.0,      # ...and 40 m at the finish
        "LobbyLength": 3000.0,      # flat waiting area behind the gates
        "CellSize": 250.0,          # snow mesh grid
        "BankHeight": 700.0,
        "BankWidth": 1200.0,
        "RidgeHeight": 500.0,       # between the two start gates
        "GateSpread": 3600.0,       # each gate this far from the middle
        "ClearPathWidth": 900.0,    # no trees on each team's racing line
        "TreeGap": 250.0,           # open snow between any two pines' crowns (wider than skis are long)
        "RunoutLength": 15000.0,    # 150 m of nearly flat run-out past the run...
        "RunoutRise": 4500.0,       # ...curving up 45 m at its end (enough to stop at top speed)
        "OuterWidth": 60000.0,      # the hills around the slope, 600 m out on every side
        # Slope|Look: the winter look, from the optional (private) Other5WinterBiome plugin; without it, cones
        "LookTree": W + "Assets/pine_trees_full/pine_tree_full_a.pine_tree_full_a",
        "LookTreeTall": W + "Assets/pine_trees_full/pine_tree_tall_full_b.pine_tree_tall_full_b",
        "LookFarTrees": W + "Assets/pine_trees_full/pine_tree_card_group_distant_a.pine_tree_card_group_distant_a",
        "LookClump": W + "Assets/snow/snow_clumps_piles/Static_Meshes/engine_snow_clumps_a_LODs.engine_snow_clumps_a_LODs",
        "LookRock": W + "Assets/rocks/rock_a/rock_a.rock_a",
        "LookMountain": W + "Assets/background_mountains/snow_mountain_low_01.snow_mountain_low_01",
        "LookMountainMaterial": W + "Materials/M_WinterSnow.M_WinterSnow",  # snow-covered (the pack's own is bare rock)
        "LookSnow": W + "Materials/M_WinterSnow.M_WinterSnow",
        "LookSnowfall": W + "Particles/Snow_FX/snow_falling.snow_falling",
        "ForestCount": 160,         # pines on the hills either side, just out of bounds (cones without the winter look)
        "FarTreeCount": 500,        # distant pines (cards) further out
        "ClumpCount": 260,          # snow clumps on the banks and hills
        "RockCount": 45,
        "MountainCount": 0,         # rings of mountains (each one mesh all round): off, the pack's ring shows thin slivers in the sky; the ridge closes the valley
        "MountainDistance": 100000.0,  # the first ring 1 km out from the middle of the slope
        # Slope|Difficulty: Easy, Medium, Hard
        "SlopeDegreesByLevel": [13.0, 19.0, 26.0],
        "BumpHeightByLevel": [12.0, 30.0, 50.0],
        "TreeCountByLevel": [60, 160, 320],
        "bBuildOnBeginPlay": True,
        "StartDifficulty": 1,
    })
    sl.set_editor_property("replicates", True)
    sl.set_editor_property("always_relevant", True)
    eal.save_loaded_asset(bp, False)
    log("slope defaults")

    bp, di = cdo("/SKIvSKI/Blueprints/BP_SkiDirector")
    set_all(di, {
        # Round|Settings
        "LobbySeconds": 15.0,
        "CountdownSeconds": 4.0,
        "RaceSeconds": 150.0,
        "ResultsSeconds": 10.0,
        "HitPoints": 1,                          # per paintball hit on the other team
        "FinishPoints": [10, 8, 6, 5, 4, 3, 2, 1],  # 1st, 2nd, ... across the finish
        "MinPlayers": 1,
        "CoinsPerPoint": 0,                      # unused since the store (2026-11-16): coins come from these two
        "HitCoins": 3,                           # for each opponent you put out
        "SurviveCoins": 10,                      # for getting through a race without being put out
    })
    di.set_editor_property("replicates", True)
    di.set_editor_property("always_relevant", True)
    eal.save_loaded_asset(bp, False)
    log("director defaults")

    # Each player's gear (Gear category): everyone starts (or joins) with the store's first gun, skis and wax, no coins.
    bp, ps = cdo("/SKIvSKI/Blueprints/BP_SkiPlayerState")
    set_all(ps, {
        "SnowFriction": 0.02,    # ski on snow, with Factory Wax (DA_WaxFactory); the store's wax lowers it
        "Coins": 0,
        "GunIndex": 0,
        "SkisIndex": 0,
        "WaxIndex": 0,
        "BounceChance": 0.10,    # this player's paintballs bounce off a target 10% of the time
    })
    eal.save_loaded_asset(bp, False)
    log("player state defaults")

    bp, fort = cdo("/SKIvSKI/Blueprints/BP_SkiFort")
    set_all(fort, {
        # Spawned by the server, seen by everyone, anywhere on the slope.
        "replicates": True,
        "always_relevant": True,
        # Fort|Layout (cm, seconds): 6 m across inside, 4.2 m deep, walls of four rows of logs with a 12 cm slit under the top row.
        "Width": 600.0,
        "Depth": 420.0,
        "FrontGap": 10.0,           # between the front wall's two logs
        "CornerGap": 26.0,          # the side walls this far out from the front wall's ends
        "RowHeights": [14.0, 42.0, 70.0, 110.0],
        "CaptureSeconds": 10.0,     # one team alone in it, from flag down to flag up
        "ExitDistance": 260.0,      # Exit fort puts you this far uphill of its open side
        "PoleX": 150.0,
        "FlagLow": 120.0,
        "FlagHigh": 520.0,
        "ProgressTeam": -1,
        "CapturedBy": -1,
        "FlagShown": -2,
    })
    bp, hud = cdo("/SKIvSKI/Blueprints/BP_SkiHUD")
    set_all(hud, {"PopupSeconds": 1.6,
                  "MapRange": 10000.0})   # the minimap shows 100 m around you   # "Hit!" / "Bounce!" pop up, fly up and fade over this long
    eal.save_loaded_asset(bp, False)

    bp, gm = cdo("/SKIvSKI/Blueprints/BP_SkiGameMode")
    # Other5's shared teams (Docs/Teams.md in Other5): listing them turns teams on for this game.
    red = unreal.Other5TeamInfo()
    red.set_editor_property("name", unreal.Text("Red"))
    red.set_editor_property("color", unreal.LinearColor(0.9, 0.08, 0.03, 1))
    blue = unreal.Other5TeamInfo()
    blue.set_editor_property("name", unreal.Text("Blue"))
    blue.set_editor_property("color", unreal.LinearColor(0.03, 0.25, 0.95, 1))
    set_all(gm, {
        "default_pawn_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiCharacter").generated_class(),
        "player_state_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiPlayerState").generated_class(),
        "player_controller_class": unreal.load_asset("/Other5Combat/Characters/BP_Other5ProjectilePlayerController").generated_class(),
        "hud_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiHUD").generated_class(),
        "teams": [red, blue],
        "auto_balance_teams": True,
        "allow_team_switch": True,
        "friendly_fire": False,
    })
    eal.save_loaded_asset(bp, False)
    log("game mode defaults")


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
