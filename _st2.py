import io, re

p = r"c:/Autolab/auto-lab/Testing/_selftest_builder.gd"
lines = io.open(p, encoding="utf-8").read().split("\n")
out = ["TOTAL LINES %d" % len(lines)]
for i, l in enumerate(lines):
    if re.match(r"\s*func ", l):
        out.append("%4d %s" % (i + 1, l.strip()))
out.append("--- helper usage ---")
for name in ["_run_interaction_checks", "_count_nodes_outside_board", "_fresh_pair",
             "_collect_controls", "_run_layout_checks", "_run_behaviour_checks"]:
    hits = [i + 1 for i, l in enumerate(lines) if name in l]
    out.append("%-28s %s" % (name, hits))
io.open(r"c:/Autolab/_st_out.txt", "w", encoding="utf-8").write("\n".join(out))
print("WROTE")