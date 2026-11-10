# SKIvSKI: the three paintball guns as data assets of BP_PaintGunData. Add a gun by copying one in the Content
# Browser and changing its numbers, then add it to BP_SkiCharacter's Guns list. Rerunnable.
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupGuns"
FOLDER = "/SKIvSKI/Guns"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

# name: (shown name, mesh, muzzle offset, speed cm/s, gravity scale, ball cm, shots/s, pellets, spread degrees, fire montage)
# Other5Combat's gun meshes point their barrels along +Y (the skier holds them turned -90 degrees, as Other5Combat
# does), so the muzzle offsets are along Y, in the mesh's own space.
GUNS = {
    # Quick and light: fast, flat-flying small balls, many shots.
    "DA_PaintPistol": ("Splat Pistol", "/Other5Combat/Weapons/Pistol/Mesh/SM_Pistol", (0, 14, 3), 7000.0, 0.5, 7.0, 6.0, 1, 0.6,
                       "/Other5Combat/Weapons/Pistol/Animations/AM_MM_Pistol_Fire"),
    # Heavy marker: big, slow, loopy balls (lead your target), two shots a second.
    "DA_PaintMarker": ("Big Marker", "/Other5Combat/Weapons/Rifle/Mesh/SM_Rifle", (0, 54, 6), 4200.0, 1.0, 14.0, 2.0, 1, 0.2,
                       "/Other5Combat/Weapons/Rifle/Animations/AM_MM_Rifle_Fire"),
    # Spread gun: six balls in a cone, slow to reload; hard to miss up close.
    "DA_PaintSpread": ("Splatter Gun", "/Other5Combat/Weapons/Shotgun/Mesh/SM_Shotgun", (0, 36, 4), 5000.0, 0.8, 7.0, 1.2, 6, 5.0,
                       "/Other5Combat/Weapons/Shotgun/Animations/AM_MM_Shotgun_Fire"),
}
# How each kind of gun is held: Other5Combat's skeletal mesh (its pivot is the grip, which sits in the hand) and
# ArmsKind, which picks the upper body's pose and aim offset in ABP_Skier (0 pistol, 1 rifle, 2 shotgun). The static
# meshes above are centred on their middle instead, so each gets a GripOffset that puts its grip back in the hand.
HOLDS = {
    "DA_PaintPistol": ("/Other5Combat/Weapons/Pistol/Mesh/SK_Pistol", 0),
    "DA_PaintMarker": ("/Other5Combat/Weapons/Rifle/Mesh/SK_Rifle", 1),
    "DA_PaintSpread": ("/Other5Combat/Weapons/Shotgun/Mesh/SKM_Shotgun", 2),
}


def grip_offset(static_mesh, skeletal_mesh):
    """Where the static mesh must sit in the hand socket so its grip is where the skeletal mesh's pivot is: the two
    meshes' centres differ by that much, turned by the -90 degree yaw the gun is held with (mesh +Y -> socket +X)."""
    box = static_mesh.get_bounding_box()
    centre = (box.min + box.max) * 0.5
    d = skeletal_mesh.get_bounds().origin - centre
    return unreal.Vector(d.y, -d.x, d.z)


# Every marker uses Other5Combat's rifle shots for now (a suppressed, paintball-like pop), one picked at random.
FIRE_SOUNDS = ["/Other5Combat/Audio/Sounds/Weapons/Rifle/Weapons_Rifle_Punch-Close_%02d" % i for i in range(1, 8)]


def main():
    data_class = unreal.load_asset(FOLDER + "/BP_PaintGunData").generated_class()
    guns = []
    for name, (label, mesh, offset, speed, grav, size, rate, pellets, spread, montage) in GUNS.items():
        path = FOLDER + "/" + name
        if eal.does_asset_exist(path):
            da = unreal.load_asset(path)
        else:
            f = unreal.DataAssetFactory()
            f.set_editor_property("data_asset_class", data_class)
            da = at.create_asset(name, FOLDER, data_class, f)
        da.set_editor_property("GunName", unreal.Text(label))
        da.set_editor_property("Mesh", unreal.load_asset(mesh))
        da.set_editor_property("MuzzleOffset", unreal.Vector(*offset))
        da.set_editor_property("MuzzleSpeed", speed)
        da.set_editor_property("BallGravityScale", grav)
        da.set_editor_property("BallSize", size)
        da.set_editor_property("ShotsPerSecond", rate)
        da.set_editor_property("PelletsPerShot", pellets)
        da.set_editor_property("SpreadDegrees", spread)
        da.set_editor_property("FireSounds", [unreal.load_asset(p) for p in FIRE_SOUNDS])
        da.set_editor_property("FireMontage", unreal.load_asset(montage))
        skeletal, kind = HOLDS[name]
        grip = grip_offset(da.get_editor_property("Mesh"), unreal.load_asset(skeletal))
        da.set_editor_property("GripOffset", grip)
        da.set_editor_property("ArmsKind", kind)
        log("%s grip %.1f %.1f %.1f" % (name, grip.x, grip.y, grip.z))
        eal.save_loaded_asset(da, False)
        guns.append(da)
        log("gun " + name)
    # The skier carries all three, in this order (Q switches).
    bp = unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiCharacter")
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    cdo = unreal.get_default_object(bp.generated_class())
    try:
        cdo.set_editor_property("Guns", guns)
        eal.save_loaded_asset(bp, False)
        log("BP_SkiCharacter.Guns set")
    except Exception as e:
        log("Guns not set yet (add the variable first): %s" % e)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
