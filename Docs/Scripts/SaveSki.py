# Saves every asset under /SKIvSKI (used by UnrealMcp.ps1 SaveSki and SaveAll). Not only the "dirty" ones: graphs written
# through BlueprintTools.write_graph_dsl don't always mark their Blueprint dirty, and a dirty-only save then skips them
# (SKIvSKI 1.1 shipped without its slope fixes that way).
import sys, unreal
M = sys.argv[1] if len(sys.argv) > 1 else "save"
ok = unreal.EditorAssetLibrary.save_directory("/SKIvSKI", only_if_is_dirty=False, recursive=True)
print("CLAUDE|%s|saved %s" % (M, ok))
print("CLAUDE|%s|END" % M)
