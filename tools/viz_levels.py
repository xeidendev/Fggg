#!/usr/bin/env python3
"""Render levels.json to PNG grid for visual verification."""
import json, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

d = json.load(open("/home/z/my-project/scripts/levels.json"))
only = [int(x) for x in sys.argv[1:]] or list(range(1, 11))
cols = 5
rows = (len(only) + cols - 1) // cols
fig, axes = plt.subplots(rows, cols, figsize=(3 * cols, 3 * rows), constrained_layout=True)
axes = [axes] if rows * cols == 1 else list(axes.flat)[: rows * cols]
for i, lvl in enumerate(only):
    ax = axes[i]
    data = d[lvl - 1]
    for ln in data["lines"]:
        pts = ln["points"]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.plot(xs, ys, color="#3A3633", lw=3, solid_capstyle="round")
        dx, dy = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
        n = (dx * dx + dy * dy) ** 0.5 or 1
        ax.arrow(pts[-1][0], pts[-1][1], dx / n * 0.25, dy / n * 0.25,
                 head_width=0.35, head_length=0.3, fc="#3A3633", ec="#3A3633")
    if data["lines"]:
        xs = [p[0] for ln in data["lines"] for p in ln["points"]]
        ys = [p[1] for ln in data["lines"] for p in ln["points"]]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        ax.set_xlim(cx - 8, cx + 8)
        ax.set_ylim(cy - 8, cy + 8)
    ax.set_aspect("equal")
    ax.set_title(f"L{lvl}", fontsize=9)
    ax.axis("off")
for j in range(len(only), rows * cols):
    axes[j].axis("off")
fig.savefig("/home/z/my-project/scripts/levels_preview.png", dpi=90)
print("saved levels_preview.png")
