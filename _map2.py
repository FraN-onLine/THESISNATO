import io, re

p = r"c:/Autolab/auto-lab/Testing/automata_builder.gd"
lines = io.open(p, encoding="utf-8", errors="replace").read().split("\n")
print("TOTAL LINES", len(lines))
for i, l in enumerate(lines):
    s = l.strip()
    if re.match(r"^(func |static func |class |enum |const |signal |@export)", l) and not l.startswith("\t"):
        print("%5d| %s" % (i + 1, s[:120]))
    elif re.match(r"^\tfunc ", l):
        print("%5d|   %s" % (i + 1, s[:120]))