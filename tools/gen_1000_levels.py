#!/usr/bin/env python3
"""v3.5.5 level generator: levels 11..1000.

Why this rewrite
----------------
The old generator scattered a handful of straight lines on an empty board:
lines crossed each other, heads sat on top of other lines, and the
difficulty fell off a cliff right after the 10 hand-made levels (40 lines at
level 10, 4 straight lines at level 11). Levels 11+ now look and play like
the originals:

  * the board is a grid packed densely with snake-shaped arrow lines;
  * every grid point belongs to at most ONE line -> no crossings, no shared
    points, no arrowhead sitting on another line;
  * an arrow never flies back over its own body;
  * coordinates are centred on the origin like the original levels;
  * difficulty grows smoothly (board size, line count, turns).

Solvability
-----------
Mechanics (lib/core/engine.dart): a fired line's head travels exactly its own
arc length L along the final segment direction; it crashes if the head circle
(r=0.2) touches another remaining line's body box (half thickness 0.1, end
caps +0.2) or head. On an integer grid that is exactly: "a grid point at
distance 1..L straight ahead of the head is occupied by another remaining
line". The generator solves each level greedily with that rule (greedy is
complete here: removing lines never blocks anything) and repairs deadlocks
by flipping a line's direction, or as a last resort dropping a line. Every
level is then re-verified with an exact port of Solver.flightIsClear (0.4
physics steps, circle-vs-box) and finally by the Dart test-suite.

Usage: python3 tools/gen_1000_levels.py assets/levels/levels.json
(reads the 10 original levels from that file and rewrites it in place)
"""
import json
import math
import random
import sys

DIRS = [(1, 0), (-1, 0), (0, 1), (0, -1)]


# ---------------------------------------------------------------- difficulty
def params(n):
    """Board/line parameters for level n (11..1000)."""
    t = (n - 11) / 989.0
    w = 8 + round(8 * t ** 0.55)            # 8 .. 16 columns
    h = round(w * 1.3) + (1 if n % 3 == 0 else 0)   # portrait 10 .. 22 rows
    max_len = 5 + round(7 * t ** 0.7)       # longest snake: 5 .. 12 points
    straight = 0.62 - 0.22 * t              # chance to keep going straight
    fill = 0.80 + 0.15 * min(1.0, t * 3)    # target board coverage
    return w, h, max_len, straight, fill


# ---------------------------------------------------------------- generation
def grow_snakes(rng, w, h, max_len, straight, fill):
    occ = {}  # (x, y) -> line id
    snakes = []
    cells = [(x, y) for x in range(w) for y in range(h)]
    rng.shuffle(cells)
    target = int(w * h * fill)
    covered = 0
    for start in cells:
        if covered >= target:
            break
        if start in occ:
            continue
        want = rng.randint(2, max_len)
        path = [start]
        taken = {start}
        d = rng.choice(DIRS)
        while len(path) < want:
            x, y = path[-1]
            opts = []
            for nd in DIRS:
                if nd == (-d[0], -d[1]):
                    continue
                nx, ny = x + nd[0], y + nd[1]
                if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in occ \
                        and (nx, ny) not in taken:
                    opts.append(nd)
            if not opts:
                break
            if d in opts and rng.random() < straight:
                nd = d
            else:
                turns = [o for o in opts if o != d] or opts
                nd = rng.choice(turns)
            d = nd
            path.append((x + d[0], y + d[1]))
            taken.add(path[-1])
        if len(path) < 2:
            continue
        sid = len(snakes)
        for c in path:
            occ[c] = sid
        snakes.append(path)
        covered += len(path)
    return snakes, occ


def ray_cells(path):
    """Grid points the head sweeps: distance 1..L ahead of the head."""
    hx, hy = path[-1]
    px, py = path[-2]
    dx, dy = hx - px, hy - py
    L = len(path) - 1
    return [(hx + dx * j, hy + dy * j) for j in range(1, L + 1)]


def self_clear(path):
    own = set(path)
    return not any(c in own for c in ray_cells(path))


def is_free(path, sid, occ, alive):
    for c in ray_cells(path):
        o = occ.get(c)
        if o is not None and o != sid and o in alive:
            return False
    return True


def solve_and_repair(rng, snakes, occ):
    """Greedy solve; flip / drop lines to break deadlocks. Mutates snakes."""
    alive = set(range(len(snakes)))
    # a line may never fly over itself: flip, else drop
    for i, p in enumerate(snakes):
        if not self_clear(p):
            p.reverse()
            if not self_clear(p):
                alive.discard(i)
    dropped = set(range(len(snakes))) - alive
    order = []
    while alive:
        free = [i for i in alive if is_free(snakes[i], i, occ, alive)]
        if free:
            for i in free:          # all free lines can go (monotone)
                if i in alive and is_free(snakes[i], i, occ, alive):
                    alive.discard(i)
                    order.append(i)
            continue
        # deadlock: flip a random line whose reverse is free and self-clear
        cand = list(alive)
        rng.shuffle(cand)
        fixed = False
        for i in cand:
            rp = list(reversed(snakes[i]))
            if self_clear(rp) and is_free(rp, i, occ, alive):
                snakes[i] = rp
                fixed = True
                break
        if not fixed:
            i = min(cand, key=lambda k: (len(snakes[k]), rng.random()))
            alive.discard(i)
            dropped.add(i)
    return [snakes[i] for i in range(len(snakes)) if i not in dropped]


def compress(path):
    """Keep only end points and corners."""
    out = [path[0]]
    for i in range(1, len(path) - 1):
        a, b, c = path[i - 1], path[i], path[i + 1]
        if (b[0] - a[0], b[1] - a[1]) != (c[0] - b[0], c[1] - b[1]):
            out.append(b)
    out.append(path[-1])
    return out


def gen_level(n):
    w, h, max_len, straight, fill = params(n)
    best = None
    for attempt in range(40):
        rng = random.Random(n * 7919 + attempt)
        snakes, occ = grow_snakes(rng, w, h, max_len, straight, fill)
        lines = solve_and_repair(rng, snakes, occ)
        cover = sum(len(p) for p in lines) / (w * h)
        score = cover
        if best is None or score > best[0]:
            best = (score, lines)
        if cover >= fill - 0.05:
            break
    lines = best[1]
    ox, oy = w // 2, h // 2
    out = []
    for p in lines:
        pts = [[x - ox, y - oy] for (x, y) in compress(p)]
        out.append({"points": pts, "speed": 20.0, "destroyDelay": 3.0})
    return out


# -------------------------------------------- exact engine parity (verifier)
HEAD_R, HALF_T, EXTRA, STEP = 0.2, 0.1, 0.2, 0.4


def circle_hits_box(c, a, b):
    cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    if L < 1e-9:
        return math.hypot(c[0] - cx, c[1] - cy) < HEAD_R
    ux, uy = dx / L, dy / L
    rx, ry = c[0] - cx, c[1] - cy
    along = rx * ux + ry * uy
    perp = rx * -uy + ry * ux
    ex = max(0.0, abs(along) - (L / 2 + EXTRA))
    ey = max(0.0, abs(perp) - HALF_T)
    return ex * ex + ey * ey < HEAD_R * HEAD_R


def flight_clear(line, others):
    pts = line["points"]
    L = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
            for i in range(len(pts) - 1))
    hx, hy = pts[-1]
    dx, dy = pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]
    dl = math.hypot(dx, dy)
    ux, uy = dx / dl, dy / dl
    samples = [STEP * k for k in range(1, int(math.floor(L / STEP)) + 1)] + [L]
    for a in samples:
        head = (hx + ux * a, hy + uy * a)
        for o in others:
            op = o["points"]
            if math.hypot(head[0] - op[-1][0], head[1] - op[-1][1]) < 2 * HEAD_R:
                return False
            for i in range(len(op) - 1):
                if circle_hits_box(head, op[i], op[i + 1]):
                    return False
    return True


def verify_solvable(lines):
    rem = list(lines)
    while rem:
        for l in rem:
            if flight_clear(l, [o for o in rem if o is not l]):
                rem.remove(l)
                break
        else:
            return False
    return True


def verify_no_shared_points(lines):
    seen = set()
    for l in lines:
        p = l["points"]
        for i in range(len(p) - 1):
            (x0, y0), (x1, y1) = p[i], p[i + 1]
            n = int(abs(x1 - x0) + abs(y1 - y0))
            for k in range(n + (1 if i == len(p) - 2 else 0)):
                c = (x0 + (x1 - x0) // n * k, y0 + (y1 - y0) // n * k)
                if c in seen:
                    return False
                seen.add(c)
    return True


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/levels/levels.json"
    data = json.load(open(path))
    originals = [lv for lv in data if lv.get("source") == "original"][:10]
    assert len(originals) == 10
    levels = list(originals)
    for n in range(11, 1001):
        lines = gen_level(n)
        assert len(lines) >= 3, n
        assert verify_no_shared_points(lines), f"level {n}: shared points"
        assert verify_solvable(lines), f"level {n}: unsolvable"
        levels.append({"level": n, "lines": lines, "source": "generated"})
        if n % 100 == 0 or n in (11, 20, 50):
            print(f"level {n}: {len(lines)} lines", flush=True)
    with open(path, "w") as f:
        json.dump(levels, f, separators=(",", ":"))
    print("wrote", path)


if __name__ == "__main__":
    main()
