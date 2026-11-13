#!/usr/bin/env python3
"""Parse Unity level prefabs from the Arrows repo into levels.json.

Mirrors the validated pipeline from the previous session:
- Read Level N.prefab (plain GameObject/Transform hierarchy + PrefabInstances)
- Instantiate referenced prefabs (Line (1)) as deep copies
- Apply PrefabInstance modifications (propertyPath, in order)
- Compute world-space polylines (level root offset baked in)
"""
import json
import os
import re
import sys

REF = "/home/z/my-project/arrows_ref"
LEVELS_DIR = os.path.join(REF, "Assets/_Game/Resources/Levels")
OUT = "/home/z/my-project/scripts/levels.json"


def parse_yaml_docs(path):
    """Split Unity YAML into {tag, id, body} docs (body = dict of key->raw string)."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    docs = []
    for chunk in re.split(r"^--- !u!\d+ &", text, flags=re.M):
        chunk = chunk.strip()
        if not chunk:
            continue
        # chunk starts with "<id>\n<tag>: ..." hmm — split removed tag; re-do properly
        docs.append(chunk)
    return text


DOC_RE = re.compile(r"^--- !u!(\d+) &(\d+)\s*$", re.M)


def load_docs(path):
    """Return list of (tag, id, body_text)."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    matches = list(DOC_RE.finditer(text))
    docs = []
    for i, m in enumerate(matches):
        tag, did = int(m.group(1)), int(m.group(2))
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        docs.append((tag, did, text[start:end].strip("\n")))
    return docs


def simple_fields(body):
    """Parse 'key: value' lines (no nesting) into dict; keep raw strings.

    Unity docs are 'TypeName:\\n  key: value' — drop header, dedent.
    """
    lines = body.split("\n")
    if lines and not lines[0].startswith((" ", "-", "m_", "serialized")):
        lines = lines[1:]
    # dedent: remove common leading spaces
    indents = [len(l) - len(l.lstrip()) for l in lines if l.strip() and not l.strip().startswith("-")]
    shift = min(indents) if indents else 0
    fields = {}
    for line in lines:
        if not line.strip():
            continue
        stripped = line[shift:] if shift else line
        if stripped.startswith(" ") or stripped.startswith("- "):
            continue
        if ":" in stripped:
            k, v = stripped.split(":", 1)
            fields[k.strip()] = v.strip()
    return fields


def parse_vec(s):
    if not s or s == "{fileID: 0}":
        return None
    out = {}
    inner = s.strip().strip("{}")
    for part in inner.split(", "):
        if ": " in part:
            k, v = part.split(": ", 1)
            out[k] = v
    return out


def parse_modifications(doc_text):
    """Extract modifications list from a PrefabInstance doc."""
    mods = []
    # each mod: "- target: {...}\n      propertyPath: X\n      value: Y"
    for m in re.finditer(
        r"- target: \{fileID: (\d+), guid: [0-9a-f]+[^\}]*\}\s*\n\s*propertyPath: ([^\n]+)\s*\n\s*value: ?([^\n]*)",
        doc_text,
    ):
        mods.append((int(m.group(1)), m.group(2).strip(), m.group(3).strip()))
    # transform parent
    tp = re.search(r"m_TransformParent: \{fileID: (\d+)\}", doc_text)
    parent = int(tp.group(1)) if tp else 0
    return parent, mods


class Node:
    def __init__(self, name):
        self.name = name
        self.pos = (0.0, 0.0, 0.0)
        self.children = []
        self.parent = None
        self.components = {}  # tag -> doc id
        self.fields = {}      # for MonoBehaviours: fileID -> fields dict


def find_meta_guid(prefab_path):
    meta = prefab_path + ".meta"
    if not os.path.exists(meta):
        return None
    with open(meta, "r", encoding="utf-8") as f:
        m = re.search(r"guid: ([0-9a-f]+)", f.read())
        return m.group(1) if m else None


def build_prefab_template(prefab_path):
    """Load a prefab file; return (root_node_template, components_by_id).

    The template is a Node tree that can be deep-copied per instance.
    """
    docs = load_docs(prefab_path)
    gameobjs = {}   # id -> fields
    transforms = {} # id -> fields
    monos = {}      # id -> fields
    lr = {}         # id -> fields (LineRenderer 120)
    for tag, did, body in docs:
        if tag == 1:
            gameobjs[did] = simple_fields(body)
        elif tag == 4:
            transforms[did] = simple_fields(body)
        elif tag == 114:
            monos[did] = simple_fields(body)
        elif tag == 120:
            lr[did] = simple_fields(body)

    # guid -> script name mapping via .meta files
    script_guids = {}
    scripts_dir = os.path.join(REF, "Assets/_Game/Scripts")
    for root, _, files in os.walk(os.path.join(REF, "Assets")):
        for fn in files:
            if fn.endswith(".cs.meta"):
                with open(os.path.join(root, fn), "r", encoding="utf-8") as f:
                    mm = re.search(r"guid: ([0-9a-f]+)", f.read())
                    if mm:
                        script_guids[mm.group(1)] = fn[:-9]

    # build nodes
    go_to_tf = {}
    for tid, tf in transforms.items():
        go_ref = parse_vec(tf.get("m_GameObject", ""))
        if go_ref:
            go_to_tf[int(go_ref.get("fileID", 0))] = tid

    nodes = {}
    for gid, go in gameobjs.items():
        name = go.get("m_Name", "?").strip()
        n = Node(name)
        tid = go_to_tf.get(gid)
        if tid is not None:
            p = parse_vec(transforms[tid].get("m_LocalPosition", ""))
            if p:
                try:
                    n.pos = (float(p.get("x", 0)), float(p.get("y", 0)), float(p.get("z", 0)))
                except ValueError:
                    n.pos = (0, 0, 0)
            n.children_tf = transforms[tid].get("m_Children", "")
        nodes[gid] = n

    # attach hierarchy
    for tid, tf in transforms.items():
        go_ref = parse_vec(tf.get("m_GameObject", ""))
        father = parse_vec(tf.get("m_Father", ""))
        if not go_ref:
            continue
        me = nodes.get(int(go_ref.get("fileID", 0)))
        if me is None:
            continue
        if father:
            fid = int(father.get("fileID", 0))
            fgo = None
            for g2, t2 in go_to_tf.items():
                if t2 == fid:
                    fgo = g2
                    break
            if fgo is not None and fgo in nodes:
                nodes[fgo].children.append(me)
                me.parent = nodes[fgo]

    return {
        "nodes": nodes,
        "transforms": transforms,
        "monos": monos,
        "lr": lr,
        "go_to_tf": go_to_tf,
        "script_guids": script_guids,
        "docs": docs,
    }


def deep_copy_template(tpl):
    """Copy nodes structure (shallow-ish: we only need LineRenderer positions + root)."""
    # For our purposes we only need, per instance: root node, its world offset,
    # and the LineRenderer m_Positions base values. Store compactly.
    return tpl


def apply_mods_to_instance(rec, mods):
    """Apply modification list to a record dict, grouped by semantics.

    - LineRenderer m_Positions (size first, then data[i]; out-of-range ignored)
    - speed / destroyDelay
    - returns (root_local_pos, root_angle_deg) gathered from per-fileID mods
    """
    lr_positions = []
    lr_size = None
    speed = None
    destroy_delay = None
    pos_by_file = {}   # fileID -> {axis: v}
    rot_by_file = {}   # fileID -> {axis: v}
    for fileid, prop, value in mods:
        if prop == "m_Positions.Array.size":
            lr_size = int(float(value))
        m = re.match(r"m_Positions\.Array\.data\[(\d+)\]\.([xy])$", prop)
        if m:
            idx, axis = int(m.group(1)), m.group(2)
            if lr_size is None or idx < lr_size:
                while len(lr_positions) <= idx:
                    lr_positions.append([0.0, 0.0])
                v = float(value) if value not in ("", "-") else 0.0
                lr_positions[idx][0 if axis == "x" else 1] = v
            continue
        if prop == "speed":
            try:
                speed = float(value)
            except ValueError:
                pass
        elif prop == "destroyDelay":
            try:
                destroy_delay = float(value)
            except ValueError:
                pass
        else:
            m = re.match(r"m_LocalPosition\.([xyz])$", prop)
            if m:
                pos_by_file.setdefault(fileid, {})["xyz".index(m.group(1))] = float(value) if value not in ("", "-") else 0.0
                continue
            m = re.match(r"m_LocalRotation\.([wxyz])$", prop)
            if m:
                rot_by_file.setdefault(fileid, {})[m.group(1)] = float(value) if value not in ("", "-") else 0.0
                continue
            m = re.match(r"m_LocalScale\.([xyz])$", prop)
            if m:
                continue  # scale handled only visually; geometry uses points
    rec["lr_positions"] = lr_positions
    rec["speed"] = speed
    rec["destroyDelay"] = destroy_delay
    rec["pos_by_file"] = pos_by_file
    rec["rot_by_file"] = rot_by_file


def walk_level(path):
    docs = load_docs(path)
    gameobjs, transforms, prefab_instances = {}, {}, []
    for tag, did, body in docs:
        if tag == 1:
            gameobjs[did] = simple_fields(body)
        elif tag == 4:
            transforms[did] = simple_fields(body)
        elif tag in (1001, 1002):  # PrefabInstance
            parent, mods = parse_modifications(body)
            prefab_instances.append({"parent": parent, "mods": mods, "docs": body})

    # guid -> prefab path
    guid_to_path = {}
    for root, _, files in os.walk(REF + "/Assets"):
        for fn in files:
            if fn.endswith(".prefab"):
                g = find_meta_guid(os.path.join(root, fn))
                if g:
                    guid_to_path[g] = os.path.join(root, fn)

    # guid of instance source comes from modifications target guid
    go_to_tf = {}
    for tid, tf in transforms.items():
        g = parse_vec(tf.get("m_GameObject", ""))
        if g:
            go_to_tf[int(g.get("fileID", 0))] = tid

    # plain node tree (world pos accumulation)
    def tf_local(tid):
        p = parse_vec(transforms[tid].get("m_LocalPosition", "")) or {}
        try:
            return (float(p.get("x", 0) or 0), float(p.get("y", 0) or 0), float(p.get("z", 0) or 0))
        except ValueError:
            return (0, 0, 0)

    # map transform id -> children transform ids
    tf_children = {tid: [] for tid in transforms}
    for tid, tf in transforms.items():
        f = parse_vec(tf.get("m_Father", ""))
        if f:
            fid = int(f.get("fileID", 0))
            if fid in tf_children:
                tf_children[fid].append(tid)

    def world_pos_of_tf(tid, _seen=None):
        _seen = _seen or set()
        if tid in _seen:
            return (0, 0, 0)
        _seen.add(tid)
        x, y, z = tf_local(tid)
        f = parse_vec(transforms[tid].get("m_Father", ""))
        if f:
            fid = int(f.get("fileID", 0))
            if fid in transforms:
                px, py, pz = world_pos_of_tf(fid, _seen)
                return (x + px, y + py, z + pz)
        return (x, y, z)

    lines = []
    tpl_cache = {}
    for inst in prefab_instances:
        mods = inst["mods"]
        # find source prefab guid
        guid = None
        for m in re.finditer(r"guid: ([0-9a-f]{32})", inst["docs"]):
            g = m.group(1)
            if g in guid_to_path:
                guid = g
                break
        if not guid:
            continue
        src = guid_to_path[guid]
        if "LineCollider" in src:
            continue
        if "Line" not in os.path.basename(src):
            continue
        if src not in tpl_cache:
            tpl_cache[src] = build_prefab_template(src)
        tpl = tpl_cache[src]

        rec = {"src": os.path.basename(src)}
        apply_mods_to_instance(rec, mods)

        # root transform fileID of the SOURCE prefab: transform with no father
        root_tf = None
        for tid, tf in tpl["transforms"].items():
            f = parse_vec(tf.get("m_Father", ""))
            if not f or int(f.get("fileID", 0)) == 0:
                root_tf = tid
                break
        if root_tf is None:
            root_tf = next(iter(rec["pos_by_file"].keys()), None)

        # parent chain world offset (plain transforms in level file)
        px, py, pz = 0.0, 0.0, 0.0
        if inst["parent"] and inst["parent"] in transforms:
            px, py, pz = world_pos_of_tf(inst["parent"])

        pos = rec["pos_by_file"].get(root_tf, {})
        rx = pos.get(0, 0.0)
        ry = pos.get(1, 0.0)
        rot = rec["rot_by_file"].get(root_tf, {})
        zw = rot.get("w", 1.0)
        zz = rot.get("z", 0.0)
        ang = 2.0 * __import__("math").atan2(zz, zw)

        wx, wy = px + rx, py + ry
        ca, sa = __import__("math").cos(ang), __import__("math").sin(ang)

        pts = rec.get("lr_positions") or []
        if len(pts) < 2:
            continue
        world_pts = [
            (round(wx + x * ca - y * sa, 4), round(wy + x * sa + y * ca, 4))
            for (x, y) in pts
        ]
        lines.append({
            "name": next((v for f, p, v in mods if p == "m_Name"), rec["src"]),
            "points": world_pts,
            "speed": rec.get("speed") or 20.0,
            "destroyDelay": rec.get("destroyDelay") or 3.0,
        })
    return lines


def main():
    levels = []
    files = sorted(
        (f for f in os.listdir(LEVELS_DIR) if re.match(r"Level \d+\.prefab$", f)),
        key=lambda f: int(re.search(r"\d+", f).group()),
    )
    for fn in files:
        n = int(re.search(r"\d+", fn).group())
        lines = walk_level(os.path.join(LEVELS_DIR, fn))
        levels.append({"level": n, "lines": lines})
        print(f"Level {n}: {len(lines)} lines")
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(levels, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
