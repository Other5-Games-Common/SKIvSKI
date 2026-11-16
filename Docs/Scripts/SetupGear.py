# SKIvSKI: the store's skis and ski wax as data assets (BP_SkiData, BP_WaxData in /SKIvSKI/Gear), listed in
# BP_SkiCharacter's Skis and Waxes in the store's order; the first of each is what everyone starts with (price 0).
# The guns are SetupGuns.py's. Rerunnable. Run in the editor after the graphs are written: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupGear"
FOLDER = "/SKIvSKI/Gear"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

# name: (shown name, price, top speed x, turning x, grip x (carving and edges), stopping x (skid braking),
#        snow friction x, length x (looks), the store's one-line description)
SKIS = {
    "DA_SkisRental": ("Rental Skis", 0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, "Everyone's first pair. Fine at everything."),
    "DA_SkisSlalom": ("Slalom Skis", 15, 0.95, 1.35, 1.3, 1.5, 1.0, 0.85,
                      "Short and sharp: turn and stop much faster, a little slower flat out."),
    "DA_SkisDownhill": ("Downhill Skis", 18, 1.12, 0.8, 0.9, 0.85, 0.8, 1.2,
                        "Long and fast: glide better and go faster, but slow to turn and stop."),
}
# name: (shown name, price, snow friction, the store's one-line description). Wax works with any skis.
WAXES = {
    "DA_WaxFactory": ("Factory Wax", 0, 0.02, "What the skis came with."),
    "DA_WaxGlide": ("Glide Wax", 6, 0.014, "A third less snow friction: keep your speed on the flats."),
    "DA_WaxRace": ("Race Wax", 14, 0.008, "The slickest: barely any snow friction."),
}


def make(name, data_class):
    path = FOLDER + "/" + name
    if eal.does_asset_exist(path):
        return unreal.load_asset(path)
    f = unreal.DataAssetFactory()
    f.set_editor_property("data_asset_class", data_class)
    log("created " + path)
    return at.create_asset(name, FOLDER, data_class, f)


def main():
    ski_class = unreal.load_asset(FOLDER + "/BP_SkiData").generated_class()
    wax_class = unreal.load_asset(FOLDER + "/BP_WaxData").generated_class()
    skis = []
    for name, (label, price, speed, turn, grip, brake, friction, length, blurb) in SKIS.items():
        da = make(name, ski_class)
        for k, v in (("SkiName", unreal.Text(label)), ("Price", price), ("SpeedScale", speed), ("TurnScale", turn),
                     ("GripScale", grip), ("BrakeScale", brake), ("FrictionScale", friction),
                     ("LengthScale", length), ("Blurb", blurb)):
            da.set_editor_property(k, v)
        eal.save_loaded_asset(da, False)
        skis.append(da)
    waxes = []
    for name, (label, price, friction, blurb) in WAXES.items():
        da = make(name, wax_class)
        for k, v in (("WaxName", unreal.Text(label)), ("Price", price), ("SnowFriction", friction), ("Blurb", blurb)):
            da.set_editor_property(k, v)
        eal.save_loaded_asset(da, False)
        waxes.append(da)
    bp = unreal.load_asset("/SKIvSKI/Blueprints/BP_SkiCharacter")
    unreal.BlueprintEditorLibrary.compile_blueprint(bp)
    cdo = unreal.get_default_object(bp.generated_class())
    cdo.set_editor_property("Skis", skis)
    cdo.set_editor_property("Waxes", waxes)
    eal.save_loaded_asset(bp, False)
    log("BP_SkiCharacter: %d skis, %d waxes" % (len(skis), len(waxes)))
    # Q's gun switching is gone (you ski with the gun you bought); its input action with it, once nothing uses it.
    old = "/SKIvSKI/Input/IA_SkiSwitchGun"
    if eal.does_asset_exist(old):
        refs = unreal.AssetRegistryHelpers.get_asset_registry().get_referencers(
            old, unreal.AssetRegistryDependencyOptions(include_hard_package_references=True))
        # The creation label (PAL_SKIvSKI) lists everything in the folder; that's no use.
        refs = [r for r in refs if not str(r).endswith("PAL_SKIvSKI")]
        if refs:
            log("IA_SkiSwitchGun still used by %s" % [str(r) for r in refs])
        else:
            eal.delete_asset(old)
            log("deleted IA_SkiSwitchGun")


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
