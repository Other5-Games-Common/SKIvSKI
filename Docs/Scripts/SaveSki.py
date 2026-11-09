# Saves every changed asset under /SKIvSKI (used by UnrealMcp.ps1 SaveSki).
import sys, unreal
M = sys.argv[1] if len(sys.argv) > 1 else "save"
ok = unreal.EditorAssetLibrary.save_directory("/SKIvSKI", only_if_is_dirty=True, recursive=True)
print("CLAUDE|%s|saved %s" % (M, ok))
print("CLAUDE|%s|END" % M)
