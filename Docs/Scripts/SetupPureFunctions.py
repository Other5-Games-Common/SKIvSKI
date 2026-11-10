# SKIvSKI: functions that only work out a value are marked Pure (no exec pins), so the graphs that use them read as
# plain values instead of one more step in the execution chain. Run before writing the graphs that call them (the
# DSL makes pure or impure call nodes from what the function is at the time). Rerunnable.
# Run in the editor: py "<this file>"
import sys
import traceback

import unreal

M = sys.argv[1] if len(sys.argv) > 1 else "SetupPureFunctions"
PURE = {
    "/SKIvSKI/Blueprints/BP_SkiHUD": ["Ink", "Muted", "Neon", "Gold", "Bad"],
}


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def main():
    for path, names in PURE.items():
        bp = unreal.load_asset(path)
        for name in names:
            editor = unreal.BlueprintGraphEditor.get_graph_editor_by_name(bp, name)
            if not editor:
                log("no function %s in %s" % (name, path))
                continue
            editor.set_is_pure_function(True)
        unreal.BlueprintEditorLibrary.compile_blueprint(bp)
        log("%s: pure %s" % (path, ", ".join(names)))


try:
    main()
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
