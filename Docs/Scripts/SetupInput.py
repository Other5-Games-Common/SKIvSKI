# SKIvSKI: makes (or refreshes) the input actions and the mapping context, all player-mappable so they show in
# Settings > Controls. Rerunnable. Run in the editor: py "<this file>"
import sys
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupInput"
FOLDER = "/SKIvSKI/Input"


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


at = unreal.AssetToolsHelpers.get_asset_tools()
eal = unreal.EditorAssetLibrary

# (asset name, mappable Name, display name, keyboard/mouse key, gamepad key)
ACTIONS = [
    ("IA_SkiDownhill", "SKIvSKI.Downhill", "Point skis downhill (speed up)", "W", "Gamepad_LeftStick_Up"),
    ("IA_SkiSlow", "SKIvSKI.Slow", "Turn across the slope (slow down)", "S", "Gamepad_LeftStick_Down"),
    ("IA_SkiLeft", "SKIvSKI.Left", "Steer left", "A", "Gamepad_LeftStick_Left"),
    ("IA_SkiRight", "SKIvSKI.Right", "Steer right", "D", "Gamepad_LeftStick_Right"),
    ("IA_SkiFire", "SKIvSKI.Fire", "Fire paintball gun", "LeftMouseButton", "Gamepad_RightTrigger"),
    ("IA_SkiSwitchGun", "SKIvSKI.SwitchGun", "Next paintball gun", "Q", "Gamepad_FaceButton_Top"),
    ("IA_SkiSwitchTeam", "SKIvSKI.SwitchTeam", "Switch team (lobby)", "T", "Gamepad_FaceButton_Left"),
    ("IA_SkiHarder", "SKIvSKI.Harder", "Admin: harder slope (lobby)", "RightBracket", "Gamepad_DPad_Up"),
    ("IA_SkiEasier", "SKIvSKI.Easier", "Admin: easier slope (lobby)", "LeftBracket", "Gamepad_DPad_Down"),
]


def get_or_create(name, cls, factory):
    path = FOLDER + "/" + name
    if eal.does_asset_exist(path):
        return unreal.load_asset(path)
    return at.create_asset(name, FOLDER, cls, factory)


def key(name):
    k = unreal.Key()
    k.set_editor_property("key_name", name)
    return k


actions = {}
for name, mappable, display, kbm, pad in ACTIONS:
    ia = get_or_create(name, unreal.InputAction, unreal.InputAction_Factory())
    ia.set_editor_property("value_type", unreal.InputActionValueType.BOOLEAN)
    ia.set_editor_property("consume_input", True)
    settings = unreal.new_object(unreal.PlayerMappableKeySettings, outer=ia)
    settings.set_editor_property("name", mappable)
    settings.set_editor_property("display_name", display)
    settings.set_editor_property("display_category", "SKIvSKI")
    ia.set_editor_property("player_mappable_key_settings", settings)
    eal.save_loaded_asset(ia, False)
    actions[name] = (ia, kbm, pad)
    log("action " + name)

imc = get_or_create("IMC_SkiVSki", unreal.InputMappingContext, unreal.InputMappingContext_Factory())
imc.unmap_all()
for name, (ia, kbm, pad) in actions.items():
    imc.map_key(ia, key(kbm))
    imc.map_key(ia, key(pad))
eal.save_loaded_asset(imc, False)
log("mappings %d" % len(imc.get_editor_property("default_key_mappings").get_editor_property("mappings")))
log("END")
