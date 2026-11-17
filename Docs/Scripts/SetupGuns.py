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
# does), so the muzzle offsets are along Y, in the mesh's own space. The order is the store's order; the first is
# what everyone starts with (price 0).
GUNS = {
    # Everyone's first gun: one ball per click, quick and flat-flying, a small magazine.
    "DA_PaintPistol": ("Splat Pistol", "/Other5Combat/Weapons/Pistol/Mesh/SM_Pistol", (0, 14, 3), 7000.0, 0.5, 7.0, 5.0, 1, 0.8,
                       "/Other5Combat/Weapons/Pistol/Animations/AM_MM_Pistol_Fire"),
    # Fast semi-auto: as quick as you can click (up to 8 a second), the most accurate and the fastest balls.
    "DA_PaintMarker": ("Snap Marker", "/Other5Combat/Weapons/Rifle/Mesh/SM_Rifle", (0, 54, 6), 8500.0, 0.4, 7.0, 8.0, 1, 0.3,
                       "/Other5Combat/Weapons/Rifle/Animations/AM_MM_Rifle_Fire"),
    # Full-auto: hold the trigger for a stream of balls, less accurate, a big magazine and a long reload.
    "DA_PaintStream": ("Stream Marker", "/Other5Combat/Weapons/Rifle/Mesh/SM_Rifle", (0, 54, 6), 7500.0, 0.5, 6.0, 11.0, 1, 2.5,
                       "/Other5Combat/Weapons/Rifle/Animations/AM_MM_Rifle_Fire"),
    # Scattergun: six balls in a cone per pump, hard to miss up close, few shells and a slow reload.
    "DA_PaintSpread": ("Scattergun", "/Other5Combat/Weapons/Rifle/Mesh/SM_Rifle", (0, 36, 4), 5500.0, 0.8, 7.0, 1.3, 6, 6.0,
                       "/Other5Combat/Weapons/Shotgun/Animations/AM_MM_Shotgun_Fire"),
}
# name: (price in coins, magazine, reload seconds, full-auto, the store's one-line description)
STORE = {
    "DA_PaintPistol": (0, 10, 1.4, False, "Everyone's first marker. One ball per click."),
    "DA_PaintMarker": (12, 16, 1.8, False, "Fast semi-auto: as quick as you click. The most accurate, the fastest balls."),
    "DA_PaintStream": (20, 30, 2.4, True, "Full-auto: hold to spray. Less accurate, big magazine, long reload."),
    "DA_PaintSpread": (16, 5, 2.6, False, "Six balls a pump: hard to miss up close. Few shells, slow reload."),
}
# Each kind of gun's reload: Other5Combat's reload montage for its kind (ArmsKind 0 pistol, 1 rifle, 2 shotgun).
RELOADS = {
    0: "/Other5Combat/Weapons/Pistol/Animations/AM_MM_Pistol_Reload",
    1: "/Other5Combat/Weapons/Rifle/Animations/AM_MM_Rifle_Reload",
    2: "/Other5Combat/Weapons/Shotgun/Animations/AM_MM_Shotgun_Reload",
}
# How each kind of gun is held: Other5Combat's skeletal mesh (its pivot is the grip, which sits in the hand) and
# ArmsKind, which picks the upper body's pose and aim offset in ABP_Skier (0 pistol, 1 rifle, 2 shotgun). The static
# meshes above are centred on their middle instead, so each gets a GripOffset that puts its grip back in the hand.
HOLDS = {
    "DA_PaintPistol": ("/Other5Combat/Weapons/Pistol/Mesh/SK_Pistol", 0),
    "DA_PaintMarker": ("/Other5Combat/Weapons/Rifle/Mesh/SK_Rifle", 1),
    "DA_PaintStream": ("/Other5Combat/Weapons/Rifle/Mesh/SK_Rifle", 1),
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
FIRE_SOUNDS = ["/Other5Combat/Template/GrenadeLauncher/Audio/FirstPersonTemplateWeaponFire02"]


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
        price, mag, reload, auto, blurb = STORE[name]
        da.set_editor_property("Price", price)
        da.set_editor_property("MagSize", mag)
        da.set_editor_property("ReloadSeconds", reload)
        da.set_editor_property("bFullAuto", auto)
        da.set_editor_property("Blurb", blurb)
        montage = unreal.load_asset(RELOADS[kind])
        if montage:
            da.set_editor_property("ReloadMontage", montage)
        else:
            log("no reload montage " + RELOADS[kind])
        log("%s grip %.1f %.1f %.1f" % (name, grip.x, grip.y, grip.z))
        eal.save_loaded_asset(da, False)
        guns.append(da)
        log("gun " + name)
    # The store sells them in this order (BP_SkiCharacter Guns; the first is everyone's starting gun).
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
