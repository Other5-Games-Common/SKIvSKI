# SKIvSKI: the forts' log, SM_SkiLog, built here from numbers (Geometry Script, nothing from Fab) with the pines' bark
# material (MI_SkiPineBark, SetupMaterials.py). Rerunnable: the mesh is rebuilt in place. BP_SkiFort stacks it into
# walls (LayLogs in Docs/Graphs/BP_SkiFort.lisp).
#
# The log, in its own space (cm): 300 long along X, centred on its origin, 14 cm round (a little wider at one end,
# like a real trunk), 12 sides. Its collision is one box round it (simple collision): skiers stop against it, paintballs
# splat on it, and the slits between rows of logs stay open. (The mesh itself as collision, a shell of triangles with
# no inside, let a skier pressed against a wall sink into it and stick, building up speed while standing still.)
import math
import sys
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "fortmesh"
MESH = "/SKIvSKI/Meshes/SM_SkiLog"
BARK = "/SKIvSKI/Materials/MI_SkiPineBark"
LENGTH = 300.0
RADIUS = 14.0
SIDES = 12


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def build():
    verts, tris, uvs = [], [], []

    def vert(x, y, z, u, v):
        verts.append(unreal.Vector(x, y, z))
        uvs.append(unreal.Vector2D(u, v))
        return len(verts) - 1

    def tri(a, b, c, inside):
        # Facing away from a point inside the log (see SetupSkiMesh.py).
        pa, pb, pc = verts[a], verts[b], verts[c]
        e1 = (pb.x - pa.x, pb.y - pa.y, pb.z - pa.z)
        e2 = (pc.x - pa.x, pc.y - pa.y, pc.z - pa.z)
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        out = (pa.x - inside[0], pa.y - inside[1], pa.z - inside[2])
        # Wound so Unreal sees the outside as the front (the opposite of a right-handed cross product; see
        # SetupSkiMesh.py's FLIP_WINDING): with it the other way the logs were drawn inside out.
        if n[0] * out[0] + n[1] * out[1] + n[2] * out[2] > 0.0:
            b, c = c, b
        tris.append(unreal.IntVector(a, b, c))

    rings = []
    for end, x in enumerate((-LENGTH / 2.0, LENGTH / 2.0)):
        r = RADIUS * (1.08 if end == 0 else 0.94)
        ring = []
        for i in range(SIDES + 1):  # the seam gets its own column of UVs
            a = 2.0 * math.pi * i / SIDES
            ring.append(vert(x, math.cos(a) * r, math.sin(a) * r, i / SIDES, end * LENGTH / 100.0))
        rings.append(ring)
    for i in range(SIDES):
        mid = (0.0, 0.0, 0.0)
        a, b, c, d = rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]
        tri(a, b, c, mid)
        tri(a, c, d, mid)
    for end, x in enumerate((-LENGTH / 2.0, LENGTH / 2.0)):
        centre = vert(x, 0.0, 0.0, 0.5, 0.5)
        inside = (x * 0.9, 0.0, 0.0)
        for i in range(SIDES):
            tri(centre, rings[end][i], rings[end][i + 1], inside)

    buffers = unreal.GeometryScriptSimpleMeshBuffers()
    buffers.set_editor_property("vertices", verts)
    buffers.set_editor_property("triangles", tris)
    buffers.set_editor_property("uv0", uvs)
    mesh = unreal.DynamicMesh()
    unreal.GeometryScript_MeshEdits.append_buffers_to_mesh(mesh, buffers, 0)
    split = unreal.GeometryScriptSplitNormalsOptions()
    split.set_editor_property("split_by_opening_angle", True)
    split.set_editor_property("opening_angle_deg", 50.0)  # round along the log, sharp at the cut ends
    unreal.GeometryScript_Normals.compute_split_normals(mesh, split, unreal.GeometryScriptCalculateNormalsOptions())
    return mesh


def main():
    mesh = build()
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
        opts.set_editor_property("enable_collision", True)
        sm, outcome = unreal.GeometryScript_NewAssetUtils.create_new_static_mesh_asset_from_mesh(mesh, MESH, opts)
        log("created %s: %s" % (MESH, outcome))
    sm.set_editor_property("static_materials", [unreal.StaticMaterial(material_interface=unreal.load_asset(BARK), material_slot_name="Bark")])
    body = sm.get_editor_property("body_setup")
    if body:
        body.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_DEFAULT)
    meshes = unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
    meshes.remove_collisions(sm)
    meshes.add_simple_collisions(sm, unreal.ScriptCollisionShapeType.BOX)
    unreal.EditorAssetLibrary.save_asset(MESH, only_if_is_dirty=False)
    log("SM_SkiLog built")


main()
log("END")
