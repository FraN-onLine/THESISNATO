import io
p = r"c:/Autolab/auto-lab/Testing/automata_builder.gd"
lines = io.open(p, encoding="utf-8").read().split("\n")
out = []


def block(title, first, last):
    out.append("========== %s (%d..%d) ==========" % (title, first, last))
    for i in range(first - 1, min(last, len(lines))):
        out.append("%5d| %s" % (i + 1, lines[i].rstrip("\r")))


# locate the helper functions we need by scanning
def find(pattern):
    for i, l in enumerate(lines):
        if pattern in l:
            return i + 1
    return -1


for name in ["func _add_mode_buttons", "func _add_node_tools", "func _add_simulate_row",
             "func _add_symbol_palette", "func _on_mode_button_pressed",
             "func _sync_mode_buttons", "func _on_palette_symbol"]:
    start = find(name)
    if start > 0:
        block(name, start, start + 26)

gc = find("class GraphCanvas")
block("GraphCanvas", gc, gc + 40)
gi = find("func _gui_input")
block("GraphCanvas._gui_input", gi, gi + 80)
out.append("GC_START=%d" % gc)
io.open(r"c:/Autolab/_ap.txt", "w", encoding="utf-8").write("\n".join(out))
print("OK")