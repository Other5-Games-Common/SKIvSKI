# SKIvSKI: the materials, all built from nodes here (no textures, nothing from Fab): snow, a colour material for
# team colours / trees / paintballs, its instances, and the paint splat decal. Rerunnable (rebuilds each graph).
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupMaterials"
FOLDER = "/SKIvSKI/Materials"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary
mel = unreal.MaterialEditingLibrary
MP = unreal.MaterialProperty


def material(name):
    path = FOLDER + "/" + name
    if eal.does_asset_exist(path):
        mat = unreal.load_asset(path)
        mel.delete_all_material_expressions(mat)
        return mat
    return at.create_asset(name, FOLDER, unreal.Material, unreal.MaterialFactoryNew())


def expr(mat, cls, x, y, **props):
    e = mel.create_material_expression(mat, cls, x, y)
    for k, v in props.items():
        e.set_editor_property(k, v)
    return e


def const(mat, value, x, y):
    return expr(mat, unreal.MaterialExpressionConstant, x, y, r=value)


def link(a, b, b_input="", a_output=""):
    mel.connect_material_expressions(a, a_output, b, b_input)


def snow():
    mat = material("M_SkiSnow")
    # Bright, faintly blue snow, a little glossy where the light hits.
    color = expr(mat, unreal.MaterialExpressionConstant3Vector, -400, 0, constant=unreal.LinearColor(0.86, 0.9, 0.97, 1))
    mel.connect_material_property(color, "", MP.MP_BASE_COLOR)
    mel.connect_material_property(const(mat, 0.55, -400, 150), "", MP.MP_ROUGHNESS)
    mel.connect_material_property(const(mat, 0.6, -400, 250), "", MP.MP_SPECULAR)
    mel.recompile_material(mat)
    eal.save_loaded_asset(mat, False)
    return mat


def color_material():
    mat = material("M_SkiColor")
    # One material for everything plain-coloured: team colours, skis, helmets, paintballs, trees.
    # Color and Roughness are parameters, so instances (MI_*) and Create Dynamic Material Instance can change them.
    c = expr(mat, unreal.MaterialExpressionVectorParameter, -400, 0, parameter_name="Color", default_value=unreal.LinearColor(1, 0.2, 0.1, 1))
    r = expr(mat, unreal.MaterialExpressionScalarParameter, -400, 200, parameter_name="Roughness", default_value=0.5)
    g = expr(mat, unreal.MaterialExpressionScalarParameter, -400, 300, parameter_name="Glow", default_value=0.0)
    mel.connect_material_property(c, "", MP.MP_BASE_COLOR)
    mel.connect_material_property(r, "", MP.MP_ROUGHNESS)
    glow = expr(mat, unreal.MaterialExpressionMultiply, -150, 300)
    link(c, glow, "A")
    link(g, glow, "B")
    mel.connect_material_property(glow, "", MP.MP_EMISSIVE_COLOR)
    mel.recompile_material(mat)
    eal.save_loaded_asset(mat, False)
    return mat


def instance(name, parent, color, roughness=0.5, glow=0.0):
    path = FOLDER + "/" + name
    if eal.does_asset_exist(path):
        mi = unreal.load_asset(path)
    else:
        mi = at.create_asset(name, FOLDER, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
    mi.set_editor_property("parent", parent)
    mel.set_material_instance_vector_parameter_value(mi, "Color", color)
    mel.set_material_instance_scalar_parameter_value(mi, "Roughness", roughness)
    mel.set_material_instance_scalar_parameter_value(mi, "Glow", glow)
    eal.save_loaded_asset(mi, False)


def splat():
    mat = material("M_PaintSplat")
    mat.set_editor_property("material_domain", unreal.MaterialDomain.MD_DEFERRED_DECAL)
    mat.set_editor_property("blend_mode", unreal.BlendMode.BLEND_TRANSLUCENT)
    # A round splat with a wobbly edge: distance from the decal's centre, pushed in and out by a sine of the angle.
    # Seed (a parameter set per splat) turns the wobble so no two splats look the same.
    uv = expr(mat, unreal.MaterialExpressionTextureCoordinate, -1200, 0)
    centre = expr(mat, unreal.MaterialExpressionConstant2Vector, -1200, 120, r=0.5, g=0.5)
    d = expr(mat, unreal.MaterialExpressionSubtract, -1000, 0)
    link(uv, d, "A")
    link(centre, d, "B")
    length = expr(mat, unreal.MaterialExpressionLength, -800, 0)
    link(d, length)
    u = expr(mat, unreal.MaterialExpressionComponentMask, -800, 150, r=True, g=False, b=False, a=False)
    v = expr(mat, unreal.MaterialExpressionComponentMask, -800, 250, r=False, g=True, b=False, a=False)
    link(d, u)
    link(d, v)
    angle = expr(mat, unreal.MaterialExpressionArctangent2, -600, 200)
    link(v, angle, "Y")
    link(u, angle, "X")
    lobes = expr(mat, unreal.MaterialExpressionMultiply, -450, 200)
    link(angle, lobes, "A")
    link(const(mat, 7.0, -600, 320), lobes, "B")
    seed = expr(mat, unreal.MaterialExpressionScalarParameter, -600, 400, parameter_name="Seed", default_value=0.0)
    turned = expr(mat, unreal.MaterialExpressionAdd, -300, 250)
    link(lobes, turned, "A")
    link(seed, turned, "B")
    wobble = expr(mat, unreal.MaterialExpressionSine, -150, 250, period=6.2831853)
    link(turned, wobble)
    wobble_size = expr(mat, unreal.MaterialExpressionMultiply, 0, 250)
    link(wobble, wobble_size, "A")
    link(const(mat, 0.07, -150, 380), wobble_size, "B")
    radius = expr(mat, unreal.MaterialExpressionAdd, 150, 150)
    link(const(mat, 0.36, 0, 120), radius, "A")
    link(wobble_size, radius, "B")
    edge = expr(mat, unreal.MaterialExpressionSubtract, 300, 0)
    link(radius, edge, "A")
    link(length, edge, "B")
    sharp = expr(mat, unreal.MaterialExpressionMultiply, 450, 0)
    link(edge, sharp, "A")
    link(const(mat, 25.0, 300, 120), sharp, "B")
    opacity = expr(mat, unreal.MaterialExpressionSaturate, 600, 0)
    link(sharp, opacity)
    mel.connect_material_property(opacity, "", MP.MP_OPACITY)
    # The colour comes from the decal component (Set Decal Color), so no material instance is needed per splat.
    c = expr(mat, unreal.MaterialExpressionDecalColor, 300, -250)
    mel.connect_material_property(c, "", MP.MP_BASE_COLOR)
    mel.connect_material_property(const(mat, 0.25, 450, -150), "", MP.MP_ROUGHNESS)
    mel.recompile_material(mat)
    eal.save_loaded_asset(mat, False)


def main():
    snow()
    base = color_material()
    instance("MI_SkiPineNeedles", base, unreal.LinearColor(0.02, 0.12, 0.05, 1), 0.85)
    instance("MI_SkiPineBark", base, unreal.LinearColor(0.12, 0.07, 0.035, 1), 0.9)
    instance("MI_SkiTeamRed", base, unreal.LinearColor(0.9, 0.08, 0.03, 1), 0.4)
    instance("MI_SkiTeamBlue", base, unreal.LinearColor(0.03, 0.25, 0.95, 1), 0.4)
    instance("MI_SkiFinish", base, unreal.LinearColor(0.95, 0.75, 0.05, 1), 0.4, 0.3)
    splat()
    log("materials done")


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
