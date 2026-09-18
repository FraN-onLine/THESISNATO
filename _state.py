import io, re, os

ROOT = r"c:/Autolab/auto-lab/Testing"
HARN = os.path.join(ROOT, "_selftest_builder.gd")
BLDR = os.path.join(ROOT, "automata_builder.gd")

out = []

har = io.open(HARN, encoding="utf-8", errors="replace").read().split("\n")
out.append("##### HARNESS (%d lines) #####" % len(har))
for i, l in enumerate(har):
    out.append("%4d| %s" % (i + 1, l.rstrip("\r")))

bl = io.open(BLDR, encoding="utf-8", errors="replace").read().split("\n")
out.append("")
out.append("##### BUILDER (%d lines) - declarations #####" % len(bl))
for i, l in enumerate(bl):
    if re.match(r"^\s*(func |class |static func |signal |enum |const |var |@export|@onready)", l):
        out.append("%4d| %s" % (i + 1, l.rstrip("\r")))

io.open(r"c:/Autolab/_state.txt", "w", encoding="utf-8").write("\n".join(out))
print("OK lines=%d" % len(out))