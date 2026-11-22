# Falling snow for SKIvSKI's skies, made from meshes and a material (no particle system), the same way as CubeEscape's
# rain and snow (CubeEscape Docs/Scripts/BuildRain.py):
#  - /SKIvSKI/Runs/Skies/FX/M_SkiStreaks: translucent streaks from Docs/Materials/M_SkiStreaks.hlsl, as bright as the
#    sky's light, never below a minimum on-screen brightness;
#  - MI_SkiSnowLight + BP_SkiSnowLight: gentle drifting flakes; MI_SkiSnowHeavy + BP_SkiSnowHeavy: a thick, fast,
#    windblown fall. Each BP has three cylinders of flakes round the camera (Close 2.5 m, Near 6 m, Far 15 m).
# A sky preset's Weather Actor (Other5 Sky Preset) spawns one on each machine and keeps it on the camera.
# Safe to rerun. Run in the editor: py "<plugin>/Docs/Scripts/BuildSnowfall.py"
import os
import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
HLSL = os.path.join(HERE, "..", "Materials", "M_SkiStreaks.hlsl")
FOLDER = "/SKIvSKI/Runs/Skies/FX"
MEL = unreal.MaterialEditingLibrary
EAL = unreal.EditorAssetLibrary
at = unreal.AssetToolsHelpers.get_asset_tools()
sub = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
lib = unreal.SubobjectDataBlueprintFunctionLibrary

# name: default (cm, cm/s or 0-1); every one is a material parameter, so a material instance can retune a layer.
PARAMS = [("Spacing", 14.0), ("Width", 1.6), ("Rows", 160.0), ("Length", 0.3), ("Speed", 1100.0), ("Density", 0.7), ("Sway", 0.0), ("Jitter", 0.25), ("Round", 0.0)]
SNOWS = {}
# Light snow: short wide dashes falling slowly and drifting side to side.
SNOWS["Light"] = {"Spacing": 40.0, "Width": 2.2, "Rows": 80.0, "Length": 0.06, "Round": 1.0, "Speed": 110.0, "Density": 0.8, "Sway": 12.0, "Jitter": 0.45, "Opacity": 1.0, "Glow": 2.4, "MinScreen": 0.85}
# A snowstorm: denser, faster, swaying more.
SNOWS["Heavy"] = {"Spacing": 24.0, "Width": 2.0, "Rows": 60.0, "Length": 0.07, "Round": 1.0, "Speed": 260.0, "Density": 0.9, "Sway": 30.0, "Jitter": 0.45, "Opacity": 1.0, "Glow": 2.4, "MinScreen": 0.85}


def log(s):
    unreal.log("BuildSnowfall: " + s)


def material():
    path = FOLDER + "/M_SkiStreaks"
    mat = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if mat is None:
        mat = at.create_asset("M_SkiStreaks", FOLDER, unreal.Material, unreal.MaterialFactoryNew())
        log("created " + path)
    MEL.delete_all_material_expressions(mat)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    mat.set_editor_property("shading_model", unreal.MaterialShadingModel.MSM_UNLIT)
    mat.set_editor_property("two_sided", True)
    with open(HLSL, encoding="utf-8") as f:
        code = "".join(line for line in f if not line.lstrip().startswith("//"))
    custom = MEL.create_material_expression(mat, unreal.MaterialExpressionCustom, -400, 0)
    custom.set_editor_property("code", code)
    custom.set_editor_property("output_type", unreal.CustomMaterialOutputType.CMOT_FLOAT1)
    custom.set_editor_property("description", "Rain streaks")
    names = ["P", "C", "T"] + [n for n, _ in PARAMS]
    inputs = []
    for name in names:
        i = unreal.CustomInput()
        i.set_editor_property("input_name", name)
        inputs.append(i)
    custom.set_editor_property("inputs", inputs)
    MEL.connect_material_expressions(MEL.create_material_expression(mat, unreal.MaterialExpressionWorldPosition, -800, -200), "", custom, "P")
    MEL.connect_material_expressions(MEL.create_material_expression(mat, unreal.MaterialExpressionObjectPositionWS, -800, -120), "", custom, "C")
    MEL.connect_material_expressions(MEL.create_material_expression(mat, unreal.MaterialExpressionTime, -800, -40), "", custom, "T")
    y = 40
    for name, value in PARAMS:
        p = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -800, y)
        p.set_editor_property("parameter_name", name)
        p.set_editor_property("default_value", value)
        MEL.connect_material_expressions(p, "", custom, name)
        y += 80
    opacity = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -400, 200)
    opacity.set_editor_property("parameter_name", "Opacity")
    opacity.set_editor_property("default_value", 0.6)
    times = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -150, 60)
    MEL.connect_material_expressions(custom, "", times, "A")
    MEL.connect_material_expressions(opacity, "", times, "B")
    MEL.connect_material_property(times, "", unreal.MaterialProperty.MP_OPACITY)
    # Unlit, as bright as the sky's light (the same whichever way you look; the sky behind it made rain toward the sun thick and away from it vanish) times Glow: streaks show against trees by day, and the night (or a storm's
    # dark sky) darkens them by itself; lit translucency went nearly invisible under a storm's dim sun.
    colour = MEL.create_material_expression(mat, unreal.MaterialExpressionVectorParameter, -400, -300)
    colour.set_editor_property("parameter_name", "Colour")
    colour.set_editor_property("default_value", unreal.LinearColor(0.85, 0.9, 1.0, 1.0))
    glow = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -400, -380)
    glow.set_editor_property("parameter_name", "Glow")
    glow.set_editor_property("default_value", 1.0)
    sky = MEL.create_material_expression(mat, unreal.MaterialExpressionSkyAtmosphereDistantLightScatteredLuminance, -400, -460)
    a = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -200, -400)
    MEL.connect_material_expressions(sky, "", a, "A")
    MEL.connect_material_expressions(glow, "", a, "B")
    # Never darker on screen than MinScreen (in screen brightness, whatever the camera exposure), so the streaks still
    # show under a dark storm sky and faintly at night.
    floor = MEL.create_material_expression(mat, unreal.MaterialExpressionScalarParameter, -400, -540)
    floor.set_editor_property("parameter_name", "MinScreen")
    floor.set_editor_property("default_value", 0.2)
    inv = MEL.create_material_expression(mat, unreal.MaterialExpressionEyeAdaptationInverse, -400, -620)
    fm = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -250, -580)
    MEL.connect_material_expressions(floor, "", fm, "A")
    MEL.connect_material_expressions(inv, "", fm, "B")
    add = MEL.create_material_expression(mat, unreal.MaterialExpressionAdd, -150, -480)
    MEL.connect_material_expressions(a, "", add, "A")
    MEL.connect_material_expressions(fm, "", add, "B")
    b = MEL.create_material_expression(mat, unreal.MaterialExpressionMultiply, -100, -340)
    MEL.connect_material_expressions(add, "", b, "A")
    MEL.connect_material_expressions(colour, "", b, "B")
    MEL.connect_material_property(b, "", unreal.MaterialProperty.MP_EMISSIVE_COLOR)
    MEL.recompile_material(mat)
    EAL.save_loaded_asset(mat, False)
    return mat


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


def snow_instance(mat, kind):
    name = "MI_SkiSnow" + kind
    path = FOLDER + "/" + name
    mi = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if mi is None:
        mi = at.create_asset(name, FOLDER, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
        log("created " + path)
    MEL.set_material_instance_parent(mi, mat)
    for k, v in SNOWS[kind].items():
        MEL.set_material_instance_scalar_parameter_value(mi, k, v)
    MEL.set_material_instance_vector_parameter_value(mi, "Colour", unreal.LinearColor(0.95, 0.96, 1.0, 1.0))
    MEL.update_material_instance(mi)
    EAL.save_loaded_asset(mi, False)
    return mi


def actor(name, mat, close=False):
    path = FOLDER + "/" + name
    bp = unreal.load_asset(path) if EAL.does_asset_exist(path) else None
    if bp is None:
        f = unreal.BlueprintFactory()
        f.set_editor_property("parent_class", unreal.Actor)
        bp = at.create_asset(name, FOLDER, unreal.Blueprint, f)
        log("created " + path)
    cylinder = unreal.load_asset("/Engine/BasicShapes/Cylinder")
    # The engine cylinder is 100 cm across and 100 cm tall: Near 6 m round, Far 15 m, both 30 m tall.
    # Snow gets a Close layer too (2.5 m), whose bigger flakes sell it.
    layers = [("Near", unreal.Vector(12, 12, 30)), ("Far", unreal.Vector(30, 30, 30))]
    if close:
        layers.insert(0, ("Close", unreal.Vector(5, 5, 30)))
    for name, scale in layers:
        c = component(bp, name, unreal.StaticMeshComponent)
        c.set_editor_property("static_mesh", cylinder)
        c.set_editor_property("override_materials", [mat])
        c.set_editor_property("relative_scale3d", scale)
        c.set_editor_property("cast_shadow", False)
        c.set_collision_profile_name("NoCollision")
        c.set_editor_property("generate_overlap_events", False)
        c.set_editor_property("can_character_step_up_on", unreal.CanBeCharacterBase.ECB_NO)
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    EAL.save_loaded_asset(bp, False)
    return bp


mat = material()
for kind in SNOWS:
    actor("BP_SkiSnow" + kind, snow_instance(mat, kind), close=True)
log("done")
