# SKIvSKI: default values of the Blueprints (tuning numbers, classes). Rerunnable; run after the graphs are written
# (the variables must exist). Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupDefaults"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


eal = unreal.EditorAssetLibrary


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
        "TeamShown": -1,             # no team colour shown yet
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
        "TopWidth": 12000.0,        # the run is 120 m wide at the top...
        "FinishWidth": 4000.0,      # ...and 40 m at the finish
        "LobbyLength": 3000.0,      # flat waiting area behind the gates
        "CellSize": 250.0,          # snow mesh grid
        "BankHeight": 700.0,
        "BankWidth": 1200.0,
        "RidgeHeight": 500.0,       # between the two start gates
        "GateSpread": 3600.0,       # each gate this far from the middle
        "ClearPathWidth": 900.0,    # no trees on each team's racing line
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
        "CoinsPerPoint": 1,                      # coins for the player per point they earn (for the shop)
    })
    di.set_editor_property("replicates", True)
    di.set_editor_property("always_relevant", True)
    eal.save_loaded_asset(bp, False)
    log("director defaults")

    # Each player's gear (Gear category): what the shop between runs will improve.
    bp, ps = cdo("/SKIvSKI/Blueprints/BP_SkiPlayerState")
    set_all(ps, {
        "SnowFriction": 0.02,    # ski on snow; ski wax will lower it
        "BounceChance": 0.10,    # this player's paintballs bounce off a target 10% of the time; better paint lowers it
    })
    eal.save_loaded_asset(bp, False)
    log("player state defaults")

    bp, hud = cdo("/SKIvSKI/Blueprints/BP_SkiHUD")
    set_all(hud, {"PopupSeconds": 1.6})   # "Hit!" / "Bounce!" pop up, fly up and fade over this long
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
