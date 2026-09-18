import io
p = r"c:/Autolab/auto-lab/Testing/_selftest_builder.gd"
lines = io.open(p, encoding="utf-8").read().split("\n")
for i in range(95, min(155, len(lines))):
    print("%4d| %s" % (i + 1, lines[i].rstrip("\r")))