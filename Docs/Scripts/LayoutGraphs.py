# SKIvSKI: lays out Blueprint graphs so people can read them, and boxes each event and function with its comment
# from the Docs/Graphs/*.lisp source. Graphs written by Unreal MCP's graph DSL arrive with every node in one row;
# run this after BuildAll.ps1 (it does) or after any write_graph_dsl. Rerunnable: it removes its own comment boxes
# (and any other comment box) and places every node again.
#
# The layout, per event or function:
#   - the execution chain runs left to right on one row, in the order it runs;
#   - each data node (no exec pins: getters, maths, Make/Break...) sits just left of and below the node that first
#     uses it, its own inputs further left, so wires are short and never run backwards across the graph;
#   - a node's second, third... exec outputs (Branch False, Is Not Valid, Cast Failed, loop Completed) start new
#     rows below everything the first output made;
#   - the event graph's events are stacked top to bottom, each in a comment box holding its comment from the .lisp
#     file; a function's comment box sits around the whole function.
# Graphs with no exec pins at all (Anim Graphs) use the editor toolset's own layered layout (arrange_nodes).
# Node sizes are estimated from titles and pin names (the editor only measures nodes it has drawn), erring large.
#
# Run in the editor: py "<this file>" [marker] [asset ...]   (no assets: every SKIvSKI Blueprint below)
import os
import re
import sys
import traceback

import unreal
from editor_toolset.toolsets.blueprint import BlueprintTools

M = sys.argv[1] if len(sys.argv) > 1 else "LayoutGraphs"
HERE = os.path.dirname(os.path.abspath(__file__))
GRAPHS = os.path.normpath(os.path.join(HERE, "..", "Graphs"))

# Blueprint -> the DSL files its graphs come from (for the comment boxes).
BLUEPRINTS = {
    "/SKIvSKI/Blueprints/BP_SkiCharacter": ["BP_SkiCharacter.Events.lisp", "BP_SkiCharacter.Movement.lisp", "BP_SkiCharacter.Paint.lisp"],
    "/SKIvSKI/Blueprints/BP_SkiDirector": ["BP_SkiDirector.lisp"],
    "/SKIvSKI/Blueprints/BP_SkiHUD": ["BP_SkiHUD.lisp"],
    "/SKIvSKI/Blueprints/BP_SkiSlope": ["BP_SkiSlope.lisp"],
    "/SKIvSKI/Blueprints/BP_Paintball": ["BP_Paintball.lisp"],
    "/SKIvSKI/Blueprints/BP_SkiPlayerState": [],
    "/SKIvSKI/Blueprints/BP_SkiGameMode": [],
    "/SKIvSKI/Animation/ABP_Skier": ["ABP_Skier.lisp"],
}

GRID = 16
XGAP = 64          # between a node and the next one to its right
YGAP = 32          # between data nodes stacked in a column
TREE_DY = 96       # data nodes start this far below their exec node's top, under its exec wire
ROWGAP = 96        # between rows of exec branches
CHAINGAP = 160     # between event boxes in the event graph
PAD = 48           # comment box padding around its nodes
COMMENT_LINE = 26  # height of one line of comment text (font size 18)
MAX_COMMENT_W = 1400


def log(s):
    print("CLAUDE|%s|%s" % (M, s))


def snap(v):
    return int(round(v / float(GRID))) * GRID


# ---- the .lisp comments ---------------------------------------------------------------------------------------

def read_doc_comments(files):
    """{('fn'|'event', name): comment text} from the ';' lines right before each top-level form."""
    docs = {}
    for f in files:
        path = os.path.join(GRAPHS, f)
        if not os.path.exists(path):
            continue
        pending = []
        depth = 0
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if depth == 0:
                    if s.startswith(";"):
                        pending.append(s.lstrip(";").strip())
                        continue
                    mm = re.match(r"^\((fn|event)\s+([^\s()]+)", s)
                    if mm:
                        text = " ".join(p for p in pending if p)
                        if text:
                            docs[(mm.group(1), mm.group(2))] = text
                    if not s:
                        pending = []
                    elif not mm:
                        pending = []
                    else:
                        pending = []
                depth += code_depth(line)
    return docs


def code_depth(line):
    """Net parenthesis depth of one line, ignoring strings and ';' comments."""
    d = 0
    in_str = False
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif c == ";":
            break
        elif c == '"':
            in_str = True
        elif c == "(":
            d += 1
        elif c == ")":
            d -= 1
        i += 1
    return d


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def wrap(text, width_px):
    chars = max(30, int(width_px / 9.5))
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > chars:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w) if cur else w
    if cur:
        lines.append(cur)
    return lines


# ---- pins and sizes -------------------------------------------------------------------------------------------

def is_exec(p):
    return str(p.get_pin_type_display_string()) == "Exec"


def ins(n):
    return [p for p in n.list_all_pins() if p.get_pin_direction() == unreal.EdGraphPinDirection.EGPD_INPUT]


def outs(n):
    return [p for p in n.list_all_pins() if p.get_pin_direction() == unreal.EdGraphPinDirection.EGPD_OUTPUT]


HIDDEN_PINS = {"WorldContextObject", "__WorldContext", "LatentInfo"}


def shown(pins, node):
    r = []
    for p in pins:
        name = str(p.get_pin_name())
        if name in HIDDEN_PINS:
            continue
        # Static library calls have a hidden 'self' pin (the library's default object).
        if name == "self" and not p.list_connected_pins() and type(node).__name__ == "K2Node_CallFunction":
            continue
        r.append(p)
    return r


def has_exec(n):
    return any(is_exec(p) for p in n.list_all_pins())


_sizes = {}


def size(n):
    key = n.get_path_name()
    if key in _sizes:
        return _sizes[key]
    cls = type(n).__name__
    title_lines = str(n.get_node_title()).split("\n")
    title = title_lines[0]
    i, o = shown(ins(n), n), shown(outs(n), n)
    rows = max(len(i), len(o), 1)
    longest_in = max([len(str(p.get_pin_name())) for p in i if not is_exec(p)] + [0])
    longest_out = max([len(str(p.get_pin_name())) for p in o if not is_exec(p) and str(p.get_pin_name()) != "ReturnValue"] + [0])
    # An unconnected input shows a value box beside its name.
    boxes = any(not is_exec(p) and not p.list_connected_pins() and str(p.get_pin_value()) not in ("", "None") for p in i)
    if cls == "K2Node_VariableGet":
        w = 8 * len(title.replace("Get ", "")) + 60
        h = 32 + 24 * max(len(i), 1)
    elif cls in ("K2Node_PromotableOperator", "K2Node_CommutativeAssociativeBinaryOperator") and len(title) <= 14 and "Append" not in title:
        w = 140 + (60 if boxes else 0)
        h = 30 + 24 * rows
    elif cls == "K2Node_Knot":
        w, h = 48, 32
    else:
        w = max(8 * max(len(t) for t in title_lines) + 60, 7 * (longest_in + longest_out) + 90 + (80 if boxes else 0), 160)
        h = 42 + 16 * (len(title_lines) - 1) + 24 * rows
    w, h = min(w, 560), h
    _sizes[key] = (w, h)
    return w, h


# ---- layout ---------------------------------------------------------------------------------------------------

class Layout:
    def __init__(self, nodes):
        self.nodes = nodes
        self.pos = {}       # path -> (x, y, w, h)
        self.by_path = {n.get_path_name(): n for n in nodes}

    def placed(self, n):
        return n.get_path_name() in self.pos

    def put(self, n, x, y):
        w, h = size(n)
        self.pos[n.get_path_name()] = (snap(x), snap(y), w, h)

    def data_sources(self, n):
        """Pure nodes feeding n's data inputs, top input first."""
        r = []
        for p in ins(n):
            if is_exec(p):
                continue
            for c in p.list_connected_pins():
                src = c.get_owning_node()
                if not has_exec(src) and src not in r:
                    r.append(src)
        return r

    def plan_tree(self, consumer, right, top, claimed):
        """Places consumer's unplaced pure inputs right-to-left. Returns (bottom, min_x, [(node, x, y)])."""
        y = top
        bottom = top
        min_x = right
        plan = []
        for s in self.data_sources(consumer):
            if self.placed(s) or s.get_path_name() in claimed:
                continue
            claimed.add(s.get_path_name())
            w, h = size(s)
            sx = right - XGAP - w
            sub_bottom, sub_min, sub_plan = self.plan_tree(s, sx, y, claimed)
            plan.append((s, sx, y))
            plan.extend(sub_plan)
            bottom = max(y + h, sub_bottom)
            min_x = min(min_x, sx, sub_min)
            y = bottom + YGAP
        return bottom, min_x, plan

    def exec_targets(self, pin):
        return [c.get_owning_node() for c in pin.list_connected_pins()]

    def place_exec(self, n, x, y):
        """Places exec node n with its data inputs starting at x, row top y. Returns (bottom, right)."""
        w, h = size(n)
        tree_bottom, tree_min, plan = self.plan_tree(n, 0, TREE_DY, set())
        nx = x - tree_min if plan else x
        self.put(n, nx, y)
        for s, sx, sy in plan:
            self.put(s, nx + sx, y + sy)
        bottom = max(y + h, y + tree_bottom if plan else y + h)
        right = nx + w
        next_x = nx + w + XGAP
        first = True
        for p in outs(n):
            if not is_exec(p):
                continue
            for t in self.exec_targets(p):
                if self.placed(t):
                    continue
                if first:
                    b, r = self.place_exec(t, next_x, y)
                    first = False
                else:
                    b, r = self.place_exec(t, next_x, bottom + ROWGAP)
                bottom = max(bottom, b)
                right = max(right, r)
        return bottom, right

    def place_rest(self, top):
        """Anything not reached from an entry (pure functions' nodes, strays): one more row."""
        x = 0
        bottom = top
        for n in self.nodes:
            if self.placed(n):
                continue
            if has_exec(n):
                b, r = self.place_exec(n, x, top)
                x = r + XGAP * 2
                bottom = max(bottom, b)
        for n in self.nodes:
            if not self.placed(n):
                # pure nodes nobody placed: a tree to the left of their first consumer that is placed, else a row
                w, h = size(n)
                self.put(n, x, top)
                x += w + XGAP
                bottom = max(bottom, top + h)
        return bottom

    def bbox(self, paths):
        xs = [self.pos[p] for p in paths]
        return (min(a[0] for a in xs), min(a[1] for a in xs), max(a[0] + a[2] for a in xs), max(a[1] + a[3] for a in xs))

    def shift(self, paths, dx, dy):
        for p in paths:
            x, y, w, h = self.pos[p]
            self.pos[p] = (x + dx, y + dy, w, h)

    def apply(self):
        for n in self.nodes:
            x, y, _, _ = self.pos[n.get_path_name()]
            n.set_node_pos(unreal.IntPoint(x, y))


def entries(nodes):
    r = []
    for n in nodes:
        pins = n.list_all_pins()
        if any(is_exec(p) and p.get_pin_direction() == unreal.EdGraphPinDirection.EGPD_OUTPUT for p in pins) and \
                not any(is_exec(p) and p.get_pin_direction() == unreal.EdGraphPinDirection.EGPD_INPUT for p in pins):
            r.append(n)
    r.sort(key=lambda n: (n.get_node_pos().y, n.get_node_pos().x))
    return r


def doc_for_entry(n, graph_name, docs):
    if graph_name != "EventGraph":
        return docs.get(("fn", graph_name), "")
    t = norm(str(n.get_node_title()).split("\n")[0])
    for (kind, name), text in docs.items():
        if kind != "event":
            continue
        k = norm(name.split("|")[-1])
        if t == k or t.endswith(k) or k.endswith(t) or t == norm("Event" + name):
            return text
    return ""


def layout_graph(graph, docs, editor):
    gname = graph.get_name()
    for c in list(editor.list_comment_nodes()):
        editor.remove_comment_node(c)
    nodes = [n for n in BlueprintTools.find_nodes(graph, "") if not isinstance(n, unreal.EdGraphNode_Comment)]
    if not nodes:
        return 0
    if not any(has_exec(n) for n in nodes):
        BlueprintTools.arrange_nodes(nodes)
        return len(nodes)
    lay = Layout(nodes)
    y = 0
    boxes = []
    for e in entries(nodes):
        if lay.placed(e):
            continue
        before = set(lay.pos)
        doc = doc_for_entry(e, gname, docs)
        b, r = lay.place_exec(e, 0, 0)
        chain = [p for p in lay.pos if p not in before]
        x1, y1, x2, y2 = lay.bbox(chain)
        lines = wrap(doc, min(max(x2 - x1, 600), MAX_COMMENT_W)) if doc else []
        head = (len(lines) * COMMENT_LINE + 24) if lines else 0
        # Move the chain so its box (with the comment text on top) starts at y.
        dy = y + PAD + head - y1
        lay.shift(chain, -x1, dy)
        x1, y1, x2, y2 = lay.bbox(chain)
        if lines:
            boxes.append(("\n".join(lines), x1 - PAD, y1 - PAD - head, (x2 - x1) + 2 * PAD, (y2 - y1) + 2 * PAD + head))
        y = y2 + PAD + CHAINGAP
    lay.place_rest(y)
    lay.apply()
    for text, x, by, w, h in boxes:
        c = editor.add_comment_node(text, unreal.Vector2D(x, by), unreal.Vector2D(w, h))
        try:
            unreal.BlueprintEditorLibrary.set_comment_color(c, unreal.LinearColor(0.12, 0.2, 0.32, 1.0))
        except Exception:
            pass
    return len(nodes)


def main(paths):
    for path in paths:
        bp = unreal.load_asset(path)
        if not bp:
            log("missing " + path)
            continue
        docs = read_doc_comments(BLUEPRINTS.get(path, []))
        bp.modify()
        total = 0
        for graph in unreal.BlueprintEditorLibrary.list_graphs(bp) if hasattr(unreal.BlueprintEditorLibrary, "list_graphs") else []:
            editor = unreal.BlueprintGraphEditor.get_graph_editor(graph)
            if not editor:
                continue
            graph.modify()
            try:
                total += layout_graph(graph, docs, editor)
            except Exception:
                log("ERROR %s:%s %s" % (path, graph.get_name(), traceback.format_exc().replace("\n", " / ")))
        unreal.BlueprintEditorLibrary.refresh_open_editors_for_blueprint(bp)
        ok = unreal.EditorAssetLibrary.save_asset(path, only_if_is_dirty=False)
        log("%s: %d nodes laid out, %d comments, saved %s" % (path, total, len(docs), ok))
    give_comments_guids(paths)


def give_comments_guids(paths):
    """Comment boxes made from Python have no NodeGuid (it's protected), which makes cooks non-deterministic
    ("missing NodeGuid ... please resave package"). A node loaded without one gets one, so: reload from disk, save."""
    sub = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem)
    packages = []
    for path in paths:
        asset = unreal.load_asset(path)
        if asset:
            sub.close_all_editors_for_asset(asset)
            packages.append(asset.get_outermost())
    unreal.EditorLoadingAndSavingUtils.reload_packages(packages, unreal.ReloadPackagesInteractionMode.ASSUME_POSITIVE)
    for path in paths:
        unreal.EditorAssetLibrary.save_asset(path, only_if_is_dirty=False)
    log("reloaded and saved %d Blueprints (comment GUIDs)" % len(packages))


try:
    main(sys.argv[2:] or list(BLUEPRINTS))
except Exception:
    log("ERROR " + traceback.format_exc().replace("\n", " / "))
log("END")
