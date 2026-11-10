# SKIvSKI: makes the Blueprint assets with their parents and components (no graphs: those are written from
# Docs/Graphs/*.lisp over Unreal MCP). Rerunnable: existing assets are kept, missing components are added.
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupBlueprints"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary
sub = unreal.get_engine_subsystem(unreal.SubobjectDataSubsystem)
lib = unreal.SubobjectDataBlueprintFunctionLibrary

BP_FOLDER = "/SKIvSKI/Blueprints"


def make_bp(name, parent, folder=BP_FOLDER):
    path = folder + "/" + name
    if eal.does_asset_exist(path):
        return unreal.load_asset(path)
    if isinstance(parent, str):
        parent = unreal.load_class(None, parent)
    f = unreal.BlueprintFactory()
    f.set_editor_property("parent_class", parent)
    bp = at.create_asset(name, folder, unreal.Blueprint, f)
    log("created " + path)
    return bp


def handles(bp):
    return sub.k2_gather_subobject_data_for_blueprint(bp)


def find(bp, comp_name):
    for h in handles(bp):
        o = lib.get_object(lib.get_data(h))
        if o and o.get_name().replace("_GEN_VARIABLE", "") == comp_name:
            return h, o
    return None, None


def add_comp(bp, comp_name, cls, parent_name=None):
    h, o = find(bp, comp_name)
    if o:
        return o
    hs = handles(bp)
    parent = hs[0]
    if parent_name:
        parent, _ = find(bp, parent_name)
    params = unreal.AddNewSubobjectParams(parent_handle=parent, new_class=cls, blueprint_context=bp)
    nh, fail = sub.add_new_subobject(params)
    if not fail.is_empty():
        log("add %s failed: %s" % (comp_name, fail))
    sub.rename_subobject(nh, unreal.Text(comp_name))
    o = lib.get_object(lib.get_data(nh))
    log("component %s.%s" % (bp.get_name(), comp_name))
    return o


def mesh(path):
    return unreal.load_asset(path)


def main():
    cube = mesh("/Engine/BasicShapes/Cube.Cube")
    sphere = mesh("/Engine/BasicShapes/Sphere.Sphere")

    # Data for each paintball gun (a Blueprint data asset class; the guns themselves are DA_Paint* assets).
    make_bp("BP_PaintGunData", "/Script/Engine.PrimaryDataAsset", "/SKIvSKI/Guns")

    # The paintball: a sphere that the Projectile Movement component flies; the sphere is the root so its hits stop it.
    ball = make_bp("BP_Paintball", "/Script/Engine.Actor")
    hs = handles(ball)
    h, o = find(ball, "Ball")
    if not o:
        params = unreal.AddNewSubobjectParams(parent_handle=hs[0], new_class=unreal.SphereComponent, blueprint_context=ball)
        nh, fail = sub.add_new_subobject(params)
        sub.rename_subobject(nh, unreal.Text("Ball"))
        h, o = find(ball, "Ball")
        log("component BP_Paintball.Ball")
    # The sphere must be the root: Projectile Movement moves (and sweeps) the root component.
    for rh in handles(ball):
        rd = lib.get_data(rh)
        ro = lib.get_object(rd)
        if ro and ro.get_name().startswith("DefaultSceneRoot"):
            sub.make_new_scene_root(hs[0], h, ball)
            sub.delete_subobject(hs[0], rh, ball)
            log("Ball is now the root")
            break
    h, o = find(ball, "Ball")
    o.set_editor_property("sphere_radius", 4.0)
    o.set_collision_profile_name("Custom")
    o.set_collision_object_type(unreal.CollisionChannel.ECC_WORLD_DYNAMIC)
    o.set_collision_enabled(unreal.CollisionEnabled.QUERY_ONLY)
    o.set_collision_response_to_all_channels(unreal.CollisionResponseType.ECR_BLOCK)
    # Balls don't hit each other (a spread shot leaves together), the camera or visibility traces.
    o.set_collision_response_to_channel(unreal.CollisionChannel.ECC_WORLD_DYNAMIC, unreal.CollisionResponseType.ECR_IGNORE)
    o.set_collision_response_to_channel(unreal.CollisionChannel.ECC_CAMERA, unreal.CollisionResponseType.ECR_IGNORE)
    o.set_collision_response_to_channel(unreal.CollisionChannel.ECC_VISIBILITY, unreal.CollisionResponseType.ECR_IGNORE)
    o.set_editor_property("can_character_step_up_on", unreal.CanBeCharacterBase.ECB_NO)
    bm = add_comp(ball, "BallMesh", unreal.StaticMeshComponent, "Ball")
    bm.set_editor_property("static_mesh", sphere)
    bm.set_editor_property("relative_scale3d", unreal.Vector(0.08, 0.08, 0.08))
    bm.set_collision_profile_name("NoCollision")
    bm.set_editor_property("cast_shadow", False)
    bm.set_material(0, unreal.load_asset("/SKIvSKI/Materials/M_SkiColor"))
    pm = add_comp(ball, "Flight", unreal.ProjectileMovementComponent)
    pm.set_editor_property("initial_speed", 0.0)
    pm.set_editor_property("max_speed", 0.0)
    pm.set_editor_property("rotation_follows_velocity", True)
    pm.set_editor_property("should_bounce", False)
    pm.set_editor_property("projectile_gravity_scale", 1.0)
    pm.set_editor_property("auto_activate", False)

    # The skier: Other5Combat's character (camera, skins, health) with skis, a helmet and a paintball gun.
    ch = make_bp("BP_SkiCharacter", "/Other5Combat/Characters/BP_Other5ProjectileCharacter.BP_Other5ProjectileCharacter_C")
    for side, y in (("SkiLeft", -13.0), ("SkiRight", 13.0)):
        s = add_comp(ch, side, unreal.StaticMeshComponent)
        s.set_editor_property("static_mesh", cube)
        s.set_editor_property("relative_location", unreal.Vector(10.0, y, -86.0))
        s.set_editor_property("relative_scale3d", unreal.Vector(1.7, 0.09, 0.025))
        s.set_collision_profile_name("NoCollision")
        s.set_material(0, unreal.load_asset("/SKIvSKI/Materials/M_SkiColor"))
    hm = add_comp(ch, "Helmet", unreal.StaticMeshComponent)
    hm.set_editor_property("static_mesh", sphere)
    hm.set_editor_property("relative_scale3d", unreal.Vector(0.27, 0.25, 0.22))
    hm.set_collision_profile_name("NoCollision")
    hm.set_material(0, unreal.load_asset("/SKIvSKI/Materials/M_SkiColor"))
    gm = add_comp(ch, "GunMesh", unreal.StaticMeshComponent)
    gm.set_collision_profile_name("NoCollision")
    # Character select: the skier's look (Other5's character skins, the same three as CubeEscape, from
    # Other5Characters), picked on joining (until the player has a fighter) and from the game menu's Fighter button.
    sk = add_comp(ch, "CharacterSkins", unreal.Other5CharacterSkins)
    skins = []
    for label, mesh_path, retargeted, retargeter, hidden, tough, speed, accuracy in (
            ("Manny", "/Other5Characters/Mannequin/Meshes/SKM_Manny", None, None, [], 5.0, 0.0, 0.0),
            ("Quinn", "/Other5Characters/Mannequin/Meshes/SKM_Quinn", None, None, [], 0.0, 0.0, 5.0),
            ("Countess", None, "/Other5Characters/Countess/Characters/Heroes/Countess/Meshes/SM_Countess",
             "/Other5Characters/Countess/Rigs/RTG_Mannequin_Countess", ["M03_Swords_holster"], 0.0, 5.0, 0.0)):
        s = unreal.Other5CharacterSkin()
        s.set_editor_property("display_name", unreal.Text(label))
        if mesh_path:
            s.set_editor_property("mesh", unreal.load_asset(mesh_path))
        if retargeted:
            s.set_editor_property("retargeted_mesh", unreal.load_asset(retargeted))
            s.set_editor_property("retargeter", unreal.load_asset(retargeter))
        s.set_editor_property("hidden_material_slots", [unreal.Name(n) for n in hidden])
        s.set_editor_property("toughness", tough)
        s.set_editor_property("speed", speed)
        s.set_editor_property("accuracy", accuracy)
        skins.append(s)
    sk.set_editor_property("skins", skins)
    sk.set_editor_property("default_skin", 0)
    sk.set_editor_property("choose_on_join", True)
    sk.set_editor_property("menu_button", True)

    make_bp("BP_SkiPlayerState", "/Script/Other5.Other5BasePlayerStateGAS")
    make_bp("BP_SkiGameMode", "/Script/Other5.Other5GameModeBase")
    make_bp("BP_SkiHUD", "/Other5Combat/UI/Hud/BP_Other5CombatHUD.BP_Other5CombatHUD_C")
    slope = make_bp("BP_SkiSlope", "/Script/Engine.Actor")
    snow = add_comp(slope, "Snow", unreal.ProceduralMeshComponent)
    snow.set_editor_property("use_complex_as_simple_collision", True)
    snow.set_material(0, unreal.load_asset("/SKIvSKI/Materials/M_SkiSnow"))
    # Snow, trees and arches are WorldStatic (BlockAll), so paintballs (which ignore WorldDynamic) splat on them.
    snow.set_collision_profile_name("BlockAll")
    # Pines from engine shapes: a cone of needles on a short cylinder trunk, one instanced mesh each (cheap to draw).
    cone = mesh("/Engine/BasicShapes/Cone.Cone")
    cylinder = mesh("/Engine/BasicShapes/Cylinder.Cylinder")
    crowns = add_comp(slope, "TreeCrowns", unreal.HierarchicalInstancedStaticMeshComponent)
    crowns.set_editor_property("static_mesh", cone)
    crowns.set_material(0, unreal.load_asset("/SKIvSKI/Materials/MI_SkiPineNeedles"))
    crowns.set_collision_profile_name("BlockAll")
    trunks = add_comp(slope, "TreeTrunks", unreal.HierarchicalInstancedStaticMeshComponent)
    trunks.set_editor_property("static_mesh", cylinder)
    trunks.set_material(0, unreal.load_asset("/SKIvSKI/Materials/MI_SkiPineBark"))
    trunks.set_collision_profile_name("BlockAll")
    # Start gates (Red team on the left, Blue on the right, looking downhill) and the finish arch: two posts and a
    # banner each, moved into place by Generate.
    for prefix, mat in (("GateRed", "MI_SkiTeamRed"), ("GateBlue", "MI_SkiTeamBlue"), ("Finish", "MI_SkiFinish")):
        m = unreal.load_asset("/SKIvSKI/Materials/" + mat)
        for part in ("PostLeft", "PostRight", "Banner"):
            c = add_comp(slope, prefix + part, unreal.StaticMeshComponent)
            c.set_editor_property("static_mesh", cube if part == "Banner" else cylinder)
            c.set_material(0, m)
            c.set_collision_profile_name("BlockAll")
    make_bp("BP_SkiDirector", "/Script/Other5.Other5GameCoordinator")

    for bp in (ball, ch, slope):
        unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    eal.save_directory("/SKIvSKI", only_if_is_dirty=True, recursive=True)
    for h in handles(ch):
        o = lib.get_object(lib.get_data(h))
        log("  char comp " + (o.get_name() if o else "?"))


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
