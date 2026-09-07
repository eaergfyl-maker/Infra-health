#!/usr/bin/env python3
# =============================================================
#  INFRASTRUCTURE HEALTH SCORE  --  PERSON C
#  Reads:  partial_a.json, partial_b.json
#  Writes: total_health.json  (for humans and for the dashboard)
#          total_health.js    (same data, so dashboard.html can be
#                              opened straight from the file manager)
#
#  Run it like this:   python3 aggregator.py
# =============================================================

import json
import os
import datetime

# Files we read and write. These names must match what Person A and
# Person B write, and what dashboard.html reads.
PARTIAL_FILES = ["partial_a.json", "partial_b.json"]
OUT_JSON = "total_health.json"
OUT_JS = "total_health.js"


def load_checks(filename):
    """Open one partial file and return the list of checks inside it."""
    if not os.path.exists(filename):
        print("WARNING: " + filename + " was not found, skipping it.")
        return []

    with open(filename) as f:
        data = json.load(f)

    return data.get("checks", [])


def rank_for(score):
    """Turn a score out of 100 into a game-style letter rank."""
    if score >= 90:
        return "S"
    if score >= 80:
        return "A"
    if score >= 70:
        return "B"
    if score >= 60:
        return "C"
    return "D"


def hostname_from(files):
    """Use the hostname recorded in the first file that has one."""
    for filename in files:
        if os.path.exists(filename):
            with open(filename) as f:
                data = json.load(f)
            if data.get("hostname"):
                return data["hostname"]
    return "unknown-host"


# ---------- 1. Collect every check from both partial files ----------

all_checks = []
for filename in PARTIAL_FILES:
    all_checks = all_checks + load_checks(filename)

if len(all_checks) == 0:
    print("ERROR: no checks found.")
    print("Run health_checks_a.sh and health_checks_b.sh first.")
    raise SystemExit(1)


# ---------- 2. Add up the points ----------

points_earned = 0
points_possible = 0
for check in all_checks:
    points_earned = points_earned + check["points"]
    points_possible = points_possible + check["max_points"]

# Score out of 100. (If only one partial file was found, this still
# works - it just scores out of what we actually measured.)
score = round(points_earned / points_possible * 100)
rank = rank_for(score)


# ---------- 3. Break the points down per category ----------

categories = {}
for check in all_checks:
    name = check["category"]
    if name not in categories:
        categories[name] = {"points": 0, "max_points": 0, "percent": 0}
    categories[name]["points"] += check["points"]
    categories[name]["max_points"] += check["max_points"]

for name in categories:
    cat = categories[name]
    cat["percent"] = round(cat["points"] / cat["max_points"] * 100)


# ---------- 4. Collect every reason we lost points ----------

lost_points = []
for check in all_checks:
    if check["points"] < check["max_points"]:
        lost_points.append({
            "category": check["category"],
            "check": check["check"],
            "lost": check["max_points"] - check["points"],
            "reason": check["reason"],
        })

# Biggest losses first, so the worst problem is at the top
lost_points.sort(key=lambda item: item["lost"], reverse=True)


# ---------- 5. Build the final report and save it ----------

report = {
    "hostname": hostname_from(PARTIAL_FILES),
    "generated_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    "score": score,
    "max_score": 100,
    "points_earned": points_earned,
    "points_possible": points_possible,
    "rank": rank,
    "categories": categories,
    "checks": all_checks,
    "lost_points": lost_points,
}

with open(OUT_JSON, "w") as f:
    json.dump(report, f, indent=2)

# The same data as a JavaScript file. This lets dashboard.html work
# even when you just double-click it (browsers block reading local
# .json files, but they allow loading a local .js file).
with open(OUT_JS, "w") as f:
    f.write("window.HEALTH_DATA = " + json.dumps(report, indent=2) + ";\n")


# ---------- 6. Print a health bar in the terminal ----------

FILLED = round(score / 5)          # 20 segments, each worth 5 points
bar = "#" * FILLED + "-" * (20 - FILLED)

print("")
print("=" * 55)
print("  HOST: " + report["hostname"] + "   " + report["generated_at"])
print("")
print("  [" + bar + "]  " + str(score) + "/100    RANK " + rank)
print("")
for name in sorted(categories):
    cat = categories[name]
    mini = "#" * round(cat["percent"] / 10) + "-" * (10 - round(cat["percent"] / 10))
    print("  %-16s [%s] %2d/%-2d" % (name, mini, cat["points"], cat["max_points"]))

if lost_points:
    print("")
    print("  Points lost:")
    for item in lost_points:
        print("   -%-3d %s: %s" % (item["lost"], item["check"], item["reason"]))
else:
    print("")
    print("  Perfect score. Nothing to fix.")

print("=" * 55)
print("")
print("Wrote " + OUT_JSON + " and " + OUT_JS)
print("Open dashboard.html in a browser to see the dashboard.")
print("")
