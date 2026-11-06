#!/usr/bin/env python3
"""Writes data/map_forest.json (the M3b forest). Edit the shapes and lists here, then run:
python3 tools/gen_forest_layout.py && godot --headless --path . --script tests/run_tests.gd
(test_layout_valid rejects spawns on water/feet and cells touching two terrains)."""
import json
import random

random.seed(5)
TREES = ["tree_round_a", "tree_round_b", "tree_round_c"]
props = []


def tree(x, y):
    x = max(8, min(1912, x))
    props.append({"id": random.choice(TREES), "at": [x, y]})


def jitter(v, d):
    return v + random.randint(-d, d)


# double staggered rows round the border (natural wall), path mouth open at the top
for x in range(30, 1880, 84):
    if not 880 <= x <= 1040:
        tree(jitter(x, 6), 96)
        tree(jitter(x + 42, 6), 160)
    tree(jitter(x, 6), 1272)
    tree(jitter(x + 42, 6), 1212)
for y in range(230, 1180, 80):
    tree(40, jitter(y, 6)); tree(104, jitter(y + 40, 6))
    tree(1880, jitter(y + 20, 6)); tree(1816, jitter(y + 60, 6))
# clumps on dark forest floor (between the clearings, like the reference)
for cx, cy, pts in [(256, 300, [(-70, 0), (0, -20), (70, 10), (-30, 60), (40, 70)]),
                    (1664, 300, [(-70, 10), (0, -20), (70, 0), (-40, 70), (30, 60)]),
                    (260, 640, [(-60, -30), (20, -50), (70, 10), (-20, 40), (50, 70)]),
                    (1660, 640, [(-70, 10), (-10, -50), (60, -30), (20, 40), (-50, 70)]),
                    (640, 230, [(-50, 0), (40, 10)]), (1280, 230, [(-40, 10), (50, 0)]),
                    (700, 690, [(0, 0)]), (1220, 690, [(0, 0)]),
                    (560, 1170, [(-40, 0), (40, 10)]), (1360, 1170, [(-40, 10), (40, 0)])]:
    for dx, dy in pts:
        tree(cx + dx, cy + dy)
for i, (x, y) in enumerate([(300, 790), (1620, 790), (780, 540), (1140, 540), (150, 470), (1770, 470),
                            (840, 860), (1080, 860), (470, 560), (1450, 560)]):
    props.append({"id": ["bush_a", "bush_b"][i % 2], "at": [x, y]})
props += [
    {"id": "well_stone", "at": [470, 260]},
    {"id": "pillar_stone", "at": [880, 820]}, {"id": "pillar_stone", "at": [1040, 820]},
    {"id": "bridge_wood", "at": [960, 1024]},
    {"id": "stump_a", "at": [620, 470]}, {"id": "stump_b", "at": [1330, 800]},
    {"id": "rock_a", "at": [640, 820]}, {"id": "rock_b", "at": [1390, 470]}, {"id": "rock_c", "at": [1110, 1120]},
    {"id": "rock_c", "at": [700, 1060]}, {"id": "rock_c", "at": [820, 300]},
    {"id": "mushroom", "at": [660, 900]}, {"id": "mushroom", "at": [1250, 1140]}, {"id": "mushroom", "at": [330, 760]},
]
flowers = [(820, 620), (1120, 460), (400, 1150), (1500, 1120), (700, 1080), (1060, 640), (540, 760), (1380, 760),
           (860, 420), (1240, 960), (680, 960), (1600, 1140), (300, 1140), (1180, 330), (740, 330)]
for i, (x, y) in enumerate(flowers):
    props.append({"id": ["flowers_b", "flowers_a"][i % 3 == 2], "at": [x, y]})

d = {"cells": [60, 40], "base": "grass",
     "terrain": [
         {"t": "forest_floor", "rect": [0, 0, 60, 5]}, {"t": "forest_floor", "rect": [0, 36, 60, 4]},
         {"t": "forest_floor", "rect": [0, 0, 4, 40]}, {"t": "forest_floor", "rect": [56, 0, 4, 40]},
         {"t": "forest_floor", "ellipse": [8, 9, 4, 2]}, {"t": "forest_floor", "ellipse": [52, 9, 4, 2]},
         {"t": "forest_floor", "ellipse": [8, 20, 4, 3]}, {"t": "forest_floor", "ellipse": [52, 20, 4, 3]},
         {"t": "stone", "rect": [29, 7, 2, 18]}, {"t": "stone", "rect": [14, 11, 15, 2]},
         {"t": "stone", "rect": [31, 11, 15, 2]},
         {"t": "water", "ellipse": [13, 30, 7, 4]}, {"t": "water", "ellipse": [47, 30, 7, 4]},
         {"t": "water", "rect": [20, 30, 20, 1]}],
     "walk": [[940, 928, 40, 96]],
     "props": props,
     "fx": [{"id": "water_ripple", "at": [380, 940]}, {"id": "water_ripple", "at": [470, 995]},
            {"id": "water_ripple", "at": [1460, 940]}, {"id": "water_ripple", "at": [1550, 995]}],
     "hero_spawn": [960, 560],
     "pack_homes": [[480, 400], [1440, 400], [960, 1110]]}
s = json.dumps(d, ensure_ascii=False)
s = s.replace('{"id"', '\n  {"id"').replace('{"t"', '\n  {"t"')
open("data/map_forest.json", "w").write(s + "\n")
print(len(props), "props")
