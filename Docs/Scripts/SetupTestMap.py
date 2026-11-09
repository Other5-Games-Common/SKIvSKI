# SKIvSKI: L_SkiTest, a plain tilted ramp to try the ski movement on (no generator, no rounds).
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupTestMap"
MAP = "/SKIvSKI/Maps/L_SkiTest"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def spawn(cls, loc, rot=unreal.Rotator(0, 0, 0)):
    return unreal.get_editor_subsystem(unreal.EditorActorSubsystem).spawn_actor_from_class(cls, loc, rot)


def add_sky():
    sun = spawn(unreal.DirectionalLight, unreal.Vector(0, 0, 1000), unreal.Rotator(0, -40, 30))
    sun.light_component.set_editor_property("atmosphere_sun_light", True)
    sun.light_component.set_editor_property("intensity", 8.0)
    spawn(unreal.SkyAtmosphere, unreal.Vector(0, 0, 0))
    sky = spawn(unreal.SkyLight, unreal.Vector(0, 0, 500))
    sky.light_component.set_editor_property("real_time_capture", True)
    sky.light_component.set_editor_property("mobility", unreal.ComponentMobility.MOVABLE)
    spawn(unreal.ExponentialHeightFog, unreal.Vector(0, 0, -2000))


def main():
    les = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
    if unreal.EditorAssetLibrary.does_asset_exist(MAP):
        les.load_level(MAP)
        log("loaded existing " + MAP)
        return
    les.new_level(MAP)
    add_sky()
    cube = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
    # 200 m long, 60 m wide ramp at 20 degrees, going down along +X, with a flat run-out at the bottom.
    ramp = spawn(unreal.StaticMeshActor, unreal.Vector(10000, 0, -3640), unreal.Rotator(0, -20, 0))  # (roll, pitch, yaw): +X end down
    ramp.static_mesh_component.set_static_mesh(cube)
    ramp.set_actor_scale3d(unreal.Vector(200, 60, 1))
    flat = spawn(unreal.StaticMeshActor, unreal.Vector(25000, 0, -7330), unreal.Rotator(0, 0, 0))
    flat.static_mesh_component.set_static_mesh(cube)
    flat.set_actor_scale3d(unreal.Vector(120, 60, 1))
    top = spawn(unreal.StaticMeshActor, unreal.Vector(-1500, 0, -50), unreal.Rotator(0, 0, 0))
    top.static_mesh_component.set_static_mesh(cube)
    top.set_actor_scale3d(unreal.Vector(30, 60, 1))
    spawn(unreal.PlayerStart, unreal.Vector(1500, 0, -380))
    ws = unreal.EditorLevelLibrary.get_editor_world().get_world_settings()
    ws.set_editor_property("default_game_mode", unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiGameMode").generated_class())
    les.save_current_level()
    log("made " + MAP)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
