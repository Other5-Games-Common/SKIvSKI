# SKIvSKI: PAL_SKIvSKI, the Primary Asset Label that puts this creation's content in its own pak chunk when the Other5
# Tool (or the Other5Publish commandlet) cooks it. Everything under /SKIvSKI is small, so the label takes the whole
# folder. Its dependencies cook into their own chunks: Other5Combat 1003, Other5Characters 1019; /Game stays in the
# base game (PAL_Other5Base). Chunk 1021 was the next free number on 2026-11-09 (1019/1020 are Characters/Creatures).
# Run in the editor: py "<this file>"
import sys
import traceback
import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupCreationLabel"
PATH = "/SKIvSKI/PAL_SKIvSKI"
CHUNK = 1021


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def main():
    eal = unreal.EditorAssetLibrary
    if eal.does_asset_exist(PATH):
        pal = unreal.load_asset(PATH)
    else:
        f = unreal.DataAssetFactory()
        f.set_editor_property("data_asset_class", unreal.PrimaryAssetLabel)
        pal = unreal.AssetToolsHelpers.get_asset_tools().create_asset("PAL_SKIvSKI", "/SKIvSKI", unreal.PrimaryAssetLabel, f)
    rules = pal.get_editor_property("rules")
    rules.set_editor_property("chunk_id", CHUNK)
    rules.set_editor_property("priority", 1)
    pal.set_editor_property("rules", rules)
    pal.set_editor_property("label_assets_in_my_directory", True)
    eal.save_loaded_asset(pal, False)
    log("PAL_SKIvSKI chunk %d" % CHUNK)


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
