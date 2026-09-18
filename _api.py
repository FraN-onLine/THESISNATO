import io

p = r"c:/Autolab/auto-lab/Testing/automata_builder.gd"
lines = io.open(p, encoding="utf-8", errors="replace").read().split("\n")
out = []
for i, l in enumerate(lines):
    s = l.rstrip("\r")
    t = s.strip()
    if t.startswith("func ") or t.startswith("class ") or t.startswith("enum ") or t.startswith("const ") or t.startswith("var ") or t.startswith("signal "):
        out.append("%5d| %s" % (i + 1, s))
io.open(r"c:/Autolab/_api.txt", "w", encoding="utf-8").write("\n".join(out))
print("TOTAL_LINES", len(lines))
print("API_ENTRIES", len(out))