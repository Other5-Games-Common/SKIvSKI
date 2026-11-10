# SKIvSKI: the HUD's fonts. Copies of Other5's UI fonts (/Game/UI/Fonts: Orbitron for titles and numbers, Exo 2 for
# the rest; same typefaces) with a bigger Legacy Font Size. The HUD canvas draws a font at its Legacy Font Size and
# then scales the letters, so Other5's 9-point fonts went blurry at the HUD's big sizes; drawn from 72 and 32 points
# and scaled down they stay sharp. BP_SkiHUD's DrawLeft / DrawCentered scale by 9 / 72 and 9 / 32 to match.
# Rerunnable. Run in the editor: py "<this file>"
import sys
import traceback

import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupFonts"
FOLDER = "/SKIvSKI/UI"
FONTS = {
    "Font_SkiTitle": ("/Game/UI/Fonts/Font_Orbitron", 72),
    "Font_SkiText": ("/Game/UI/Fonts/Font_Exo2", 32),
}


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def main():
    eal = unreal.EditorAssetLibrary
    for name, (source, size) in FONTS.items():
        path = FOLDER + "/" + name
        if not eal.does_asset_exist(path):
            eal.duplicate_asset(source, path)
        font = unreal.load_asset(path)
        font.set_editor_property("legacy_font_size", size)
        eal.save_asset(path, only_if_is_dirty=False)
        log("%s: %s at %d points" % (path, source, size))


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
