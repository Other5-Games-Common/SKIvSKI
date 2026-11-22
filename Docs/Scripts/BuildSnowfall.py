# Falling snow for SKIvSKI's skies, made from an instanced mesh and a material (no particle system):
#  - /SKIvSKI/Runs/Skies/FX/M_SkiFlakes: one small square per flake, moved by Docs/Materials/M_SkiFlakesMove.hlsl
#    (World Position Offset) so each flake is fixed in the world, falling and drifting, and turned to face the camera;
#    a soft round flake from M_SkiFlakesLook.hlsl, as bright as the sky's light, never below a minimum on-screen
#    brightness. Every number is a material parameter, so a material instance retunes it.
#  - MI_SkiFlakesLight + BP_SkiFlakesLight: gentle drifting flakes; MI_SkiFlakesHeavy + BP_SkiFlakesHeavy: a thick,
#    windblown storm. Each BP is one Instanced Static Mesh (Flakes) holding Count flakes spread through a Box cm cube.
# A sky preset's Weather Actor (Other5 Sky Preset) spawns one on each machine and keeps it on the camera; the flakes
# wrap round the camera, so you ski through them at any speed (2026-11-22: the earlier cylinders of streaks round the
# camera, BP_SkiSnow*, moved with you, so snow fell straight down however fast you went, and the close cylinder looked
# like a bubble). Safe to rerun. Run in the editor: py "<plugin>/Docs/Scripts/BuildSnowfall.py"
import os
import random
import sys
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "BuildSnowfall"
HERE = os.path.dirname(os.path.abspath(__file__))
MATERIALS = os.path.join(HERE, "..", "Materials")
FOLDER = "/SKIvSKI/Runs/Skies/FX"
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
sub = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
lib = unreal.SubobjectDataBlueprintFunctionLibrary

# Material parameters and their defaults (cm, cm/s).
PARAMS = [("Box", 2400.0), ("Size", 3.0), ("Speed", 120.0), ("Sway", 15.0), ("WindX", 0.0), ("WindY", 0.0), ("Near", 40.0), ("MinAngle", 0.005)]
SNOWS = {
    # Light snow: slow, drifting flakes.
    "Light": {"Count": 9000, "Box": 2400.0, "Size": 5.0, "MinAngle": 0.005, "Speed": 110.0, "Sway": 15.0, "WindX": 0.0, "WindY": 40.0, "Near": 40.0,
              "Opacity": 0.9, "Glow": 2.4, "MinScreen": 0.85},
    # A snowstorm: denser, faster, windblown.
    "Heavy": {"Count": 30000, "Box": 2400.0, "Size": 6.5, "MinAngle": 0.005, "Speed": 260.0, "Sway": 35.0, "WindX": 0.0, "WindY": 220.0, "Near": 40.0,
              "Opacity": 0.9, "Glow": 2.4, "MinScreen": 0.85},
}
# The old camera cylinders, removed once the skies point at the new actors (SetupRuns.py).
OLD = ["BP_SkiSnowLight", "BP_SkiSnowHeavy", "MI_SkiSnowLight", "MI_SkiSnowHeavy", "M_SkiStreaks"]


def log(s):
    unreal.log("CLAUDE|%s|%s" % (M, s))


def code(name):
    with open(os.path.join(MATERIALS, name), encoding="utf-8") as f:
        return "".join(line for line in f if not line.lstrip().startswith("//"))


def custom(mat, name, out_type, inputs, x, y):
    c = MEL.create_material_expression(mat, unreal.MaterialExpressionCustom, x, y)
    c.set_editor_property("code", code(name))
    c.set_editor_property("output_type", out_type)
    c.set_editor_property("description", name.replace(".hlsl", ""))
    ins = []
    for n in inputs:
        i = unreal.CustomInput()
        i.set_editor_property("input_name", n)
        ins.append(i)
    c.set_editor_property("inputs", ins)
    return c


def vec(mat, value, x, y):
    c = MEL.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, x, y)
    c.set_editor_property("constant", unreal.LinearColor(value[0], value[1], value[2], 0.0))
    return c


def material():
    path = FOLDER + "/M_SkiFlakes"
    mat = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if mat is None:
        mat = at.create_asset("M_SkiFlakes", FOLDER, unreal.Material, unreal.MaterialFactoryNew())
        log("created " + path)
    MEL.delete_all_material_expressions(mat)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("two_sided", True)
    mat.set_editor_property("used_with_instanced_static_meshes", True)
    params = {}
    y = 300
    for name, value in PARAMS:
        p = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -1200, y)
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", value)
        params[name] = p
        y += 70
    uv = MEL.create_material_expression(mat, unreal.MaterialExpressionTextureCoordinate, -1200, 0)
    cam = MEL.create_material_expression(mat, unreal.MaterialExpressionCameraPositionWS, -1200, 80)
    time = MEL.create_material_expression(mat, unreal.MaterialExpressionTime, -1200, 160)
    # The flake moved: World Position Offset.
    move = custom(mat, "M_SkiFlakesMove.hlsl", unreal.CustomMaterialOutputType.CMOT_FLOAT3,
                  ["R", "Cam", "Right", "Up", "UV", "P", "T", "Box", "Size", "Speed", "Sway", "WindX", "WindY", "MinAngle"], -500, 400)
    seed = MEL.create_material_expression(mat, unreal.MaterialExpressionPerInstanceRandom, -900, 200)
    vertex = MEL.create_material_expression(mat, unreal.MaterialExpressionWorldPosition, -900, 320)
    vertex.set_editor_property("world_position_shader_offset", unreal.WorldPositionIncludedOffsets.WPT_EXCLUDE_ALL_SHADER_OFFSETS)
    axes = []
    for i, v in enumerate(((1, 0, 0), (0, 1, 0))):
        t = MEL.create_material_expression(mat, unreal.MaterialExpressionTransform, -900, 380 + 60 * i)
        t.set_editor_property("transform_source_type", unreal.MaterialVectorCoordTransformSource.TRANSFORMSOURCE_VIEW)
        t.set_editor_property("transform_type", unreal.MaterialVectorCoordTransform.TRANSFORM_WORLD)
        MEL.connect_material_expressions(vec(mat, v, -1100, 380 + 60 * i), "", t, "")
        axes.append(t)
    for src, pin in ((seed, "R"), (cam, "Cam"), (axes[0], "Right"), (axes[1], "Up"), (uv, "UV"), (vertex, "P"), (time, "T")):
        MEL.connect_material_expressions(src, "", move, pin)
    for name in ("Box", "Size", "Speed", "Sway", "WindX", "WindY", "MinAngle"):
        MEL.connect_material_expressions(params[name], "", move, name)
    MEL.connect_material_property(move, "", unreal.MaterialProperty.MP_WORLD_POSITION_OFFSET)
    # The flake's look: Opacity.
    look = custom(mat, "M_SkiFlakesLook.hlsl", unreal.CustomMaterialOutputType.CMOT_FLOAT1, ["UV", "P", "Cam", "Box", "Near"], -500, 0)
    pixel = MEL.create_material_expression(mat, unreal.MaterialExpressionWorldPosition, -900, -60)
    for src, pin in ((uv, "UV"), (pixel, "P"), (cam, "Cam"), (params["Box"], "Box"), (params["Near"], "Near")):
        MEL.connect_material_expressions(src, "", look, pin)
    opacity = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -500, 120)
    opacity.set_editor_property("parameter_name", "Opacity")
    opacity.set_editor_property("default_value", 0.9)
    times = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -250, 60)
    MEL.connect_material_expressions(look, "", times, "A")
    MEL.connect_material_expressions(opacity, "", times, "B")
    MEL.connect_material_property(times, "", unreal.MaterialProperty.MP_OPACITY)
    # Unlit, as bright as the sky's light times Glow (so night and a storm's dark sky darken it by themselves), and never
    # darker on screen than MinScreen whatever the camera exposure, so flakes still show under a dark storm.
    colour = MEL.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -500, -300)
    colour.set_editor_property("parameter_name", "Colour")
    colour.set_editor_property("default_value", unreal.LinearColor(0.95, 0.96, 1.0, 1.0))
    glow = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -500, -380)
    glow.set_editor_property("parameter_name", "Glow")
    glow.set_editor_property("default_value", 1.0)
    sky = MEL.create_material_expression(mat, unreal.MaterialExpressionSkyAtmosphereDistantLightScatteredLuminance, -500, -460)
    a = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -300, -400)
    MEL.connect_material_expressions(sky, "", a, "A")
    MEL.connect_material_expressions(glow, "", a, "B")
    floor = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -500, -540)
    floor.set_editor_property("parameter_name", "MinScreen")
    floor.set_editor_property("default_value", 0.2)
    inv = MEL.create_material_expression(mat, unreal.MaterialExpressionEyeAdaptationInverse, -500, -620)
    fm = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -350, -580)
    MEL.connect_material_expressions(floor, "", fm, "A")
    MEL.connect_material_expressions(inv, "", fm, "B")
    add = MEL.create_material_expression(mat, unreal.MaterialExpressionAdd, -250, -480)
    MEL.connect_material_expressions(a, "", add, "A")
    MEL.connect_material_expressions(fm, "", add, "B")
    b = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -150, -340)
    MEL.connect_material_expressions(add, "", b, "A")
    MEL.connect_material_expressions(colour, "", b, "B")
    MEL.connect_material_property(b, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    MEL.recompile_material(mat)
    EAL.save_loaded_asset(mat, False)
    return mat


def instance(mat, kind):
    name = "MI_SkiFlakes" + kind
    path = FOLDER + "/" + name
    mi = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if mi is None:
        mi = at.create_asset(name, FOLDER, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
        log("created " + path)
    MEL.set_material_instance_parent(mi, mat)
    for k, v in SNOWS[kind].items():
        if k != "Count":
            MEL.set_material_instance_scalar_parameter_value(mi, k, v)
    MEL.update_material_instance(mi)
    EAL.save_loaded_asset(mi, False)
    return mi


def handles(bp):
    return sub.k2_gather_subobject_data_for_blueprint(bp)


def component(bp, name, cls):
    for h in handles(bp):
        o = lib.get_object(lib.get_data(h))
        if o and o.get_name().replace("_GEN_VARIABLE", "") == name:
            return o
    params = unreal.AddNewSubobjectParams(parent_handle=handles(bp)[0], new_class=cls, blueprint_context=bp)
    nh, fail = sub.add_new_subobject(params)
    if not fail.is_empty():
        log("add %s failed: %s" % (name, fail))
    sub.rename_subobject(nh, unreal.Text(name))
    log("component %s.%s" % (bp.get_name(), name))
    return lib.get_object(lib.get_data(nh))


def actor(kind, mi):
    name = "BP_SkiFlakes" + kind
    path = FOLDER + "/" + name
    bp = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if bp is None:
        f = unreal.BlueprintFactory()
        f.set_editor_property("parent_class", unreal.Actor)
        bp = at.create_asset(name, FOLDER, unreal.Blueprint, f)
        log("created " + path)
    ism = component(bp, "Flakes", unreal.InstancedStaticMeshComponent)
    ism.set_editor_property("static_mesh", unreal.load_asset("/Engine/BasicShapes/Plane"))
    ism.set_editor_property("override_materials", [mi])
    ism.set_editor_property("cast_shadow", False)
    ism.set_collision_profile_name("NoCollision")
    ism.set_editor_property("generate_overlap_events", False)
    ism.set_editor_property("can_character_step_up_on", unreal.CanBeCharacterBase.ECB_NO)
    # The flakes are drawn round the camera, wherever the instances themselves are, so each instance's bounds must
    # cover the whole cube (a full-size square, its bounds scaled up): small ones were culled as too small to see.
    ism.set_editor_property("bounds_scale", SNOWS[kind]["Box"] / 100.0 * 1.5)
    ism.set_editor_property("never_distance_cull", True)
    ism.clear_instances()
    rng = random.Random(1021 + len(kind))
    half = SNOWS[kind]["Box"] * 0.5
    ts = []
    for _ in range(SNOWS[kind]["Count"]):
        ts.append(unreal.Transform(unreal.Vector(rng.uniform(-half, half), rng.uniform(-half, half), rng.uniform(-half, half)), unreal.Rotator(0, 0, 0), unreal.Vector(1, 1, 1)))
    ism.add_instances(ts, False, False)
    log("%s: %d flakes" % (name, ism.get_instance_count()))
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    EAL.save_loaded_asset(bp, False)
    return bp


try:
    mat = material()
    for kind in SNOWS:
        actor(kind, instance(mat, kind))
    if "--remove-old" in sys.argv:
        for name in OLD:
            path = FOLDER + "/" + name
            if EAL.does_asset_exist(path):
                log("delete %s: %s" % (name, EAL.delete_asset(path)))
except Exception as e:
    import traceback
    log("ERROR " + traceback.format_exc().replace("\n", " | "))
log("END")
