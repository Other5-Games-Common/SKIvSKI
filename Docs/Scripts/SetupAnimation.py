# SKIvSKI: ABP_Skier, the skier's Animation Blueprint (Manny skeleton). Its graphs are written from
# Docs/Graphs/ABP_Skier.lisp over Unreal MCP. Rerunnable: an existing asset is kept.
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupAnimation"
FOLDER = "/SKIvSKI/Animation"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def main():
    path = FOLDER + "/ABP_Skier"
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        abp = unreal.load_asset(path)
    else:
        mesh = unreal.load_asset("/Other5Characters/Mannequin/Meshes/SKM_Manny")
        f = unreal.AnimBlueprintFactory()
        f.set_editor_property("target_skeleton", mesh.skeleton)
        f.set_editor_property("parent_class", unreal.AnimInstance)
        abp = unreal.AssetToolsHelpers.get_asset_tools().create_asset("ABP_Skier", FOLDER, unreal.AnimBlueprint, f)
        log("created " + path)
    for g in unreal.BlueprintEditorLibrary.get_graphs(abp) if hasattr(unreal.BlueprintEditorLibrary, "get_graphs") else []:
        log("graph " + g.get_name())
    unreal.EditorAssetLibrary.save_loaded_asset(abp, False)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))


def setup_layer_blend():
    # Upper body (spine_01 and everything above it) from Other5's own animation, so aiming and holding the gun work
    # as usual; the legs from the ski stance. Mesh-space rotation keeps the chest facing where the camera aims even
    # though the crouched pelvis tilts forward.
    # BuildAnimGraph.ps1 makes a new node each run, so its number changes: take the highest that exists.
    node = None
    for i in range(64):
        found = unreal.find_object(None, FOLDER + "/ABP_Skier.ABP_Skier:AnimGraph.AnimGraphNode_LayeredBoneBlend_%d" % i)
        if found:
            node = found
    if not node:
        log("no layered blend node yet: run BuildAnimGraph.ps1 first")
        return
    anim_node = node.get_editor_property("node")
    flt = unreal.BranchFilter()
    flt.set_editor_property("bone_name", "spine_01")
    flt.set_editor_property("blend_depth", 0)
    pose = unreal.InputBlendPose()
    pose.set_editor_property("branch_filters", [flt])
    anim_node.set_editor_property("layer_setup", [pose])
    anim_node.set_editor_property("mesh_space_rotation_blend", True)
    node.set_editor_property("node", anim_node)
    abp = unreal.load_asset(FOLDER + "/ABP_Skier")
    unreal.BlueprintEditorLibrary.compile_blueprint(abp)
    unreal.EditorAssetLibrary.save_loaded_asset(abp, False)
    log("layer blend: spine_01 up from the base animation")


try:
    setup_layer_blend()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))


def set_anim_node(path, **values):
    # An Anim Graph node's settings live in its "node" struct (a copy): change it, then put it back.
    node = unreal.find_object(None, path)
    if not node:
        log("no node " + path)
        return
    anim_node = node.get_editor_property("node")
    for k, v in values.items():
        anim_node.set_editor_property(k, v)
    node.set_editor_property("node", anim_node)


def bone(name):
    ref = unreal.BoneReference()
    ref.set_editor_property("bone_name", name)
    return ref


def setup_nodes():
    # BuildAnimGraph.ps1 leaves which node is which in %TEMP%/SKIvSKI/AnimNodes.json.
    import json, os, tempfile
    which_file = os.path.join(tempfile.gettempdir(), "SKIvSKI", "AnimNodes.json")
    if not os.path.exists(which_file):
        log("no AnimNodes.json yet: run BuildAnimGraph.ps1 first")
        return
    with open(which_file, encoding="utf-8-sig") as f:
        which = json.load(f)
    # The montage slots: Other5Combat's fire montages (AM_MM_*_Fire, set on each gun in SetupGuns.py) are additive
    # recoil in FullBodyAdditivePreAim, applied before the aim offset as Other5Combat does; its reload montages
    # (AM_MM_*_Reload) are on UpperBody.
    set_anim_node(which["FireSlot"], slot_name="FullBodyAdditivePreAim")
    set_anim_node(which["ReloadSlot"], slot_name="UpperBody")
    # The legs (see BuildAnimGraph.ps1): the pelvis lowered (its translation added, in component space), the feet put on
    # the skis by Two Bone IK (targets in component space, no stretching), then turned along the skis (their rotation
    # replaced, in component space).
    cs = unreal.BoneControlSpace.BCS_COMPONENT_SPACE
    ignore = unreal.BoneModificationMode.BMM_IGNORE
    for key in ("PelvisDown", "PelvisCrouch"):
        set_anim_node(which[key], bone_to_modify=bone("pelvis"),
                      translation_mode=unreal.BoneModificationMode.BMM_ADDITIVE, translation_space=cs,
                      rotation_mode=ignore, scale_mode=ignore)
    for key, name in (("IkLeft", "foot_l"), ("IkRight", "foot_r")):
        set_anim_node(which[key], ik_bone=bone(name), effector_location_space=cs,
                      joint_target_location_space=cs, allow_stretching=False)
    for key, name in (("FootLeft", "foot_l"), ("FootRight", "foot_r")):
        set_anim_node(which[key], bone_to_modify=bone(name),
                      rotation_mode=unreal.BoneModificationMode.BMM_REPLACE, rotation_space=cs,
                      translation_mode=ignore, scale_mode=ignore)
    abp = unreal.load_asset(FOLDER + "/ABP_Skier")
    unreal.BlueprintEditorLibrary.compile_blueprint(abp)
    unreal.EditorAssetLibrary.save_asset(FOLDER + "/ABP_Skier", only_if_is_dirty=False)
    log("slots, pelvis, foot IK and foot turns set")


try:
    setup_nodes()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
