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
        "TopSpeed": 2500.0,          # cm/s at full pull (90 km/h)
        "FullInputAccel": 600.0,     # cm/s^2 of gravity pull that counts as full input (and the Max Acceleration)
        "TurnRate": 110.0,           # degrees per second the skis turn
        "CarveGrip": 2.5,            # Ground Friction: how fast the velocity follows the skis
        "SkidBraking": 450.0,        # cm/s^2 lost when skidding (skis across, or turning off the fall line)
        "SkidFriction": 0.4,         # extra braking that grows with speed
        "SkateInput": 0.12,          # W on flat snow
        "AcrossHoldSeconds": 0.35,   # S pauses this long with the skis across the slope
        "MaxLean": 25.0,             # degrees the body leans into a turn
    })
    # The movement component's own defaults must match the tuning: Other5's Speed stat (fighter progression) sets
    # Max Walk Speed from the class default whenever it changes, so a value set only at Begin Play doesn't last.
    cmc = ch.get_editor_property("character_movement")
    set_all(cmc, {
        "max_walk_speed": 2500.0,
        "max_acceleration": 600.0,
        "ground_friction": 2.5,
        "braking_deceleration_walking": 450.0,
        "use_separate_braking_friction": True,
        "braking_friction": 0.4,
    })
    eal.save_loaded_asset(bp, False)
    log("character defaults, max walk speed %.0f" % cmc.get_editor_property("max_walk_speed"))

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
