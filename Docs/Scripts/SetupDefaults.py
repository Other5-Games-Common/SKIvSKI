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
        "SnowFriction": 0.05,        # waxed skis on packed snow
        "TopSpeed": 3000.0,          # cm/s at full pull (108 km/h)
        "FullInputAccel": 450.0,     # cm/s^2 of gravity pull that counts as full input (and the Max Acceleration)
        "TurnRate": 110.0,           # degrees per second the skis turn
        "CarveGrip": 2.5,            # Ground Friction: how fast the velocity follows the skis
        "SkidBraking": 450.0,        # cm/s^2 lost when skidding (skis across, or turning off the fall line)
        "SkidFriction": 0.4,         # extra braking that grows with speed
        "SkateInput": 0.12,          # W on flat snow
        "AcrossHoldSeconds": 0.35,   # S pauses this long with the skis across the slope
        "MaxLean": 25.0,             # degrees the body leans into a turn
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
    })
    di.set_editor_property("replicates", True)
    di.set_editor_property("always_relevant", True)
    eal.save_loaded_asset(bp, False)
    log("director defaults")

    bp, gm = cdo("/SKIvSKI/Blueprints/BP_SkiGameMode")
    set_all(gm, {
        "default_pawn_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiCharacter").generated_class(),
        "player_state_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiPlayerState").generated_class(),
        "player_controller_class": unreal.load_asset("/Other5Combat/Characters/BP_Other5ProjectilePlayerController").generated_class(),
        "hud_class": unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiHUD").generated_class(),
    })
    eal.save_loaded_asset(bp, False)
    log("game mode defaults")


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
