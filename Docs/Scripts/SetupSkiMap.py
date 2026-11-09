# SKIvSKI: the game level L_SkiVSki: sky, the slope at the origin (it builds itself), player starts in the lobby
# and the director (rounds and teams) if its Blueprint exists. Rerunnable: opens the level and adds what's missing.
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupSkiMap"
MAP = "/SKIvSKI/Maps/L_SkiVSki"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


eas = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def spawn(cls, loc, rot=unreal.Rotator(0, 0, 0)):
    return eas.spawn_actor_from_class(cls, loc, rot)


def find(cls):
    return [a for a in eas.get_all_level_actors() if isinstance(a, cls)]


def bp_class(path):
    if not unreal.EditorAssetLibrary.does_asset_exist(path):
        return None
    return unreal.load_asset(path).generated_class()


def main():
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    if unreal.EditorAssetLibrary.does_asset_exist(MAP):
        les.load_level(MAP)
    else:
        les.new_level(MAP)
    world = unreal.EditorLevelLibrary.get_editor_world()
    if not world.get_path_name().startswith(MAP):
        raise RuntimeError("wrong world open: " + world.get_path_name())
    if not find(unreal.DirectionalLight):
        # Afternoon sun from behind the start, so the slope is lit as you look down it.
        sun = spawn(unreal.DirectionalLight, unreal.Vector(0, 0, 2000), unreal.Rotator(0, -35, 160))
        sun.light_component.set_editor_property("atmosphere_sun_light", True)
        sun.light_component.set_editor_property("intensity", 9.0)
        spawn(unreal.SkyAtmosphere, unreal.Vector(0, 0, 0))
        sky = spawn(unreal.SkyLight, unreal.Vector(0, 0, 800))
        sky.light_component.set_editor_property("real_time_capture", True)
        sky.light_component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
        fog = spawn(unreal.ExponentialHeightFog, unreal.Vector(0, 0, -20000))
        fog.component.set_editor_property("fog_density", 0.01)
        log("sky")
    slope_cls = bp_class("/SKIvSKI/Blueprints/BP_SkiSlope")
    if not [a for a in eas.get_all_level_actors() if a.get_class() == slope_cls]:
        spawn(slope_cls, unreal.Vector(0, 0, 0))
        log("slope")
    if not find(unreal.PlayerStart):
        # In the lobby (behind the start gates, flat snow at height 0), facing downhill.
        for i in range(8):
            spawn(unreal.PlayerStart, unreal.Vector(-1800 + (i // 4) * 300, (i % 4 - 1.5) * 300, 120))
        log("player starts")
    director_cls = bp_class("/SKIvSKI/Blueprints/BP_SkiDirector")
    if director_cls and not [a for a in eas.get_all_level_actors() if a.get_class() == director_cls]:
        spawn(director_cls, unreal.Vector(-2500, 0, 300))
        log("director")
    ws = world.get_world_settings()
    ws.set_editor_property("default_game_mode", bp_class("/SKIvSKI/Blueprints/BP_SkiGameMode"))
    # The slope can be 200 m below the start; keep the kill height well under it.
    ws.set_editor_property("kill_z", -60000.0)
    les.save_current_level()
    log("saved " + MAP)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
