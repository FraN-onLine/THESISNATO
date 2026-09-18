import io, re, sys

targets = [
    (r"c:/Autolab/auto-lab/Testing/_selftest_builder.gd", "HARNESS", [(100, 155)]),
    (r"c:/Autolab/auto-lab/Testing/automata_builder.gd", "BUILDER",
     [(238, 300), (371, 440), (455, 560), (985, 1060), (1307, 1400)]),
]
out = []
for path, tag, ranges in targets:
    lines = io.open(path, encoding="utf-8", errors="replace").read().split("\n")
    for a, b in ranges:
        out.append("========== %s %d..%d ==========" % (tag, a, b))
        for i in range(a - 1, min(b, len(lines))):
            out.append("%5d| %s" % (i + 1, lines[i].rstrip("\r")))
io.open(r"c:/Autolab/_ctx.txt", "w", encoding="utf-8").write("\n".join(out))
print("WROTE", len(out))