# SKIvSKI: the skis' mesh, SM_Ski, built here from numbers (Geometry Script, nothing from Fab), and the skier's two ski
# components set to use it. Rerunnable: the mesh is rebuilt in place.
#
# The ski, in its own space (cm): X along the ski toward the tip, Y across, Z up. Its origin is on the running surface
# under the middle of the boot, so placing the ski at a point on the snow puts it on the snow there, and tilting it to
# the snow tilts it about that point. Real skis' shapes:
#   - 172 cm long, the boot 6 cm behind the middle (the tail is at -80, the tip at +92);
#   - a sidecut: 9.4 cm wide at the tail, 7 cm under the boot, 10.6 cm at the shovel, rounded at both ends;
#   - the tip curves up 9 cm over its last 28 cm, the tail 2.5 cm over its last 8;
#   - 1.9 cm thick under the boot, thinning to 1 cm at the ends, with bevelled top edges;
#   - a binding: a plate under the boot (the sole rests on it, SOLE_HEIGHT above the running surface) and toe and heel
#     pieces. The bindings are material slot 1 (M_SkiBinding, dark); the ski itself is slot 0 (M_SkiColor, which
#     UpdateTeamLook tints with the team's colour, on every slot that has a Color parameter: M_SkiBinding has none).
# ABP_Skier puts each foot on its ski's binding from these numbers (SoleHeight, in SetupAnimation.py).
import math
import sys
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "skimesh"
MESH = "/SKIvSKI/Meshes/SM_Ski"
BINDING_MAT = "/SKIvSKI/Materials/M_SkiBinding"
CHARACTER = "/SKIvSKI/Blueprints/BP_SkiCharacter"

TAIL, TIP = -80.0, 92.0
# Unreal's front faces are the other way round from a right-handed cross product: measured on the built meshes
# (GeometryScript face normals of the top triangles pointed down until this was True).
FLIP_WINDING = True
PLATE = 1.2              # binding plate thickness
SOLE_HEIGHT = 1.9 + PLATE  # the boot's sole above the running surface, at the boot

# Where the skis go on the skier (actor space, cm); BP_SkiCharacter's SkiStance / BindingForward (Ski|Tuning) and
# its UpdateSlope / PlaceSkis use the same numbers.
STANCE = 12.0            # each ski's middle this far either side of the skier's middle
BINDING_FORWARD = 11.0   # the boots this far ahead of the capsule's middle (the ankles 7 cm behind them)
REST_Z = -90.5           # the running surface below the capsule's middle when standing on flat snow


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def width(x):
    if x < -70.0:   # the tail, rounded
        return max(9.4 * math.sqrt(max(0.0, 1.0 - ((x + 70.0) / 10.5) ** 2)), 3.0)
    if x < 0.0:     # tail to waist: the sidecut
        return 7.0 + 2.4 * (x / -70.0) ** 2
    if x < 65.0:    # waist to shovel
        return 7.0 + 3.6 * (x / 65.0) ** 2
    return max(10.6 * math.sqrt(max(0.0, 1.0 - ((x - 65.0) / 27.5) ** 2)), 1.5)  # the tip, rounded


def base(x):
    if x > 64.0:
        return 9.0 * ((x - 64.0) / (TIP - 64.0)) ** 2
    if x < -72.0:
        return 2.5 * ((-72.0 - x) / (-72.0 - TAIL)) ** 2
    return 0.0


def thickness(x):
    return max(1.0 + 0.9 * (1.0 - (x / 80.0) ** 2), 0.8)


def stations():
    xs, x = [], TAIL
    while x < TIP - 0.01:
        xs.append(x)
        x += 1.0 if (x < -70.0 or x > 60.0) else 4.0
    xs.append(TIP)
    return xs


class Builder:
    def __init__(self):
        self.verts, self.tris, self.uvs = [], [], []

    def vert(self, x, y, z):
        self.verts.append(unreal.Vector(x, y, z))
        self.uvs.append(unreal.Vector2D((x - TAIL) / (TIP - TAIL), y / 12.0 + 0.5))
        return len(self.verts) - 1

    def tri(self, a, b, c, inside):
        # Every triangle faces away from a point inside its part (wound so the cross product of its first two edges
        # points out), so none is culled from the outside. FLIP_WINDING turns them all if Unreal's sense is the other.
        pa, pb, pc = (self.verts[i] for i in (a, b, c))
        e1 = (pb.x - pa.x, pb.y - pa.y, pb.z - pa.z)
        e2 = (pc.x - pa.x, pc.y - pa.y, pc.z - pa.z)
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        out = (pa.x - inside[0], pa.y - inside[1], pa.z - inside[2])
        if (n[0] * out[0] + n[1] * out[1] + n[2] * out[2] < 0.0) != FLIP_WINDING:
            b, c = c, b
        self.tris.append(unreal.IntVector(a, b, c))

    def quad(self, a, b, c, d, inside):
        self.tri(a, b, c, inside)
        self.tri(a, c, d, inside)

    def fan(self, ring, inside):
        for i in range(1, len(ring) - 1):
            self.tri(ring[0], ring[i], ring[i + 1], inside)

    def buffers(self):
        b = unreal.GeometryScriptSimpleMeshBuffers()
        b.set_editor_property("vertices", self.verts)
        b.set_editor_property("triangles", self.tris)
        b.set_editor_property("uv0", self.uvs)
        return b


def ski_body():
    # Each station is a ring of 6 points: bottom left, bottom right, then the top with bevelled edges.
    b = Builder()
    rings = []
    for x in stations():
        h, z0, t = width(x) / 2.0, base(x), thickness(x)
        rings.append([b.vert(x, -h, z0), b.vert(x, h, z0), b.vert(x, h, z0 + t * 0.55),
                      b.vert(x, h * 0.82, z0 + t), b.vert(x, -h * 0.82, z0 + t), b.vert(x, -h, z0 + t * 0.55)])
    centres = [middle(b, r) for r in rings]
    for k, (r0, r1) in enumerate(zip(rings, rings[1:])):
        inside = tuple((p + q) / 2.0 for p, q in zip(centres[k], centres[k + 1]))
        for i in range(6):
            j = (i + 1) % 6
            b.quad(r0[i], r1[i], r1[j], r0[j], inside)
    # The end caps: inside is a little way back into the ski from each end.
    b.fan(rings[0], tuple(p + (0.5 if n == 0 else 0.0) for n, p in enumerate(centres[0])))
    b.fan(rings[-1], tuple(p - (0.5 if n == 0 else 0.0) for n, p in enumerate(centres[-1])))
    return b


def middle(b, ring):
    pts = [b.verts[i] for i in ring]
    return (sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), sum(p.z for p in pts) / len(pts))


def box(b, x0, x1, y0, y1, z0, z1):
    c = [b.vert(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    # c index: x + 2y + 4z
    inside = ((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0)
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        b.quad(*[c[i] for i in q], inside)


def bindings():
    b = Builder()
    top = 1.9  # the ski's top under the boot
    box(b, -15.0, 15.0, -3.4, 3.4, top, top + PLATE)               # plate under the boot
    box(b, 11.0, 16.5, -3.6, 3.6, top + PLATE, top + PLATE + 2.6)  # toe piece
    box(b, -17.0, -11.0, -3.6, 3.6, top + PLATE, top + PLATE + 3.4)  # heel piece
    return b


def binding_material():
    if unreal.EditorAssetLibrary.does_asset_exist(BINDING_MAT):
        return unreal.load_asset(BINDING_MAT)
    mel = unreal.MaterialEditingLibrary
    mat = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        "M_SkiBinding", "/SKIvSKI/Materials", unreal.Material, unreal.MaterialFactoryNew())
    color = mel.create_material_expression(mat, unreal.MaterialExpressionConstant3Vector, -300, 0)
    color.set_editor_property("constant", unreal.LinearColor(0.025, 0.026, 0.03, 1.0))
    rough = mel.create_material_expression(mat, unreal.MaterialExpressionConstant, -300, 150)
    rough.set_editor_property("r", 0.45)
    metal = mel.create_material_expression(mat, unreal.MaterialExpressionConstant, -300, 250)
    metal.set_editor_property("r", 0.35)
    mel.connect_material_property(color, "", unreal.MaterialProperty.MP_BASE_COLOR)
    mel.connect_material_property(rough, "", unreal.MaterialProperty.MP_ROUGHNESS)
    mel.connect_material_property(metal, "", unreal.MaterialProperty.MP_METALLIC)
    mel.recompile_material(mat)
    unreal.EditorAssetLibrary.save_asset(BINDING_MAT, only_if_is_dirty=False)
    log("made " + BINDING_MAT)
    return mat


def build_mesh():
    gs = unreal.GeometryScript_MeshEdits
    mesh = unreal.DynamicMesh()
    gs.append_buffers_to_mesh(mesh, ski_body().buffers(), 0)
    gs.append_buffers_to_mesh(mesh, bindings().buffers(), 1)
    # Smooth along the ski's curves, sharp at its edges and the bindings' corners.
    split = unreal.GeometryScriptSplitNormalsOptions()
    split.set_editor_property("split_by_opening_angle", True)
    split.set_editor_property("opening_angle_deg", 35.0)
    unreal.GeometryScript_Normals.compute_split_normals(mesh, split, unreal.GeometryScriptCalculateNormalsOptions())
    if unreal.EditorAssetLibrary.does_asset_exist(MESH):
        sm = unreal.load_asset(MESH)
        opts = unreal.GeometryScriptCopyMeshToAssetOptions()
        opts.set_editor_property("enable_recompute_normals", False)
        opts.set_editor_property("enable_recompute_tangents", True)
        opts.set_editor_property("replace_materials", False)
        unreal.GeometryScript_AssetUtils.copy_mesh_to_static_mesh(mesh, sm, opts, unreal.GeometryScriptMeshWriteLOD())
    else:
        opts = unreal.GeometryScriptCreateNewStaticMeshAssetOptions()
        opts.set_editor_property("enable_recompute_normals", False)
        opts.set_editor_property("enable_collision", False)
        sm, outcome = unreal.GeometryScript_NewAssetUtils.create_new_static_mesh_asset_from_mesh(mesh, MESH, opts)
        log("created %s: %s" % (MESH, outcome))
    mats = [unreal.StaticMaterial(material_interface=unreal.load_asset("/SKIvSKI/Materials/M_SkiColor"), material_slot_name="Ski"),
            unreal.StaticMaterial(material_interface=binding_material(), material_slot_name="Binding")]
    sm.set_editor_property("static_materials", mats)
    unreal.EditorAssetLibrary.save_asset(MESH, only_if_is_dirty=False)
    log("SM_Ski: %d vertices, %d triangles" % (mesh.get_vertex_count() if hasattr(mesh, "get_vertex_count") else -1,
                                                mesh.get_triangle_count() if hasattr(mesh, "get_triangle_count") else -1))
    return sm


def fit_character(sm):
    bp = unreal.load_asset(CHARACTER)
    sub = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
    lib = unreal.SubobjectDataBlueprintFunctionLibrary
    found = 0
    for h in sub.k2_gather_subobject_data_for_blueprint(bp):
        data = lib.get_data(h)
        name = str(lib.get_variable_name(data))
        if name not in ("SkiLeft", "SkiRight"):
            continue
        comp = lib.get_object(data)
        side = -STANCE if name == "SkiLeft" else STANCE
        comp.set_editor_property("static_mesh", sm)
        comp.set_editor_property("override_materials", [])
        comp.set_editor_property("relative_location", unreal.Vector(BINDING_FORWARD, side, REST_Z))
        comp.set_editor_property("relative_scale3d", unreal.Vector(1.0, 1.0, 1.0))
        comp.set_editor_property("cast_shadow", True)
        found += 1
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    unreal.EditorAssetLibrary.save_asset(CHARACTER, only_if_is_dirty=False)
    log("skis on the character: %d" % found)


def main():
    sm = build_mesh()
    fit_character(sm)


main()
log("END")
