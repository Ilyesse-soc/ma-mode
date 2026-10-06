"""Append authored clothing to byte-preserved canonical mannequins.

Requires the Blender output from build_reference_clothing.py for both profiles.
Only the new dressing assets are written. No network, credentials or providers.
"""
import copy
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    size, kind = struct.unpack_from("<II", raw, 12)
    assert kind == 0x4E4F534A
    document = json.loads(raw[20:20 + size])
    bin_size, bin_kind = struct.unpack_from("<II", raw, 20 + size)
    assert bin_kind == 0x004E4942
    return document, raw[28 + size:28 + size + bin_size]


def build(sex):
    source = ROOT / f"apps/mobile/assets/3d/mannequins/{sex}.glb"
    body, body_bin = read_glb(source)
    clothes, clothes_bin = read_glb(ROOT / f".tmp/reference-clothing/{sex}-clothes.glb")
    doc = copy.deepcopy(body)
    tables = ["bufferViews", "accessors", "images", "samplers", "textures", "materials", "meshes", "nodes"]
    offsets = {key: len(doc.get(key, [])) for key in tables}
    bin_offset = (len(body_bin) + 3) // 4 * 4
    for key in tables:
        entries = copy.deepcopy(clothes.get(key, []))
        for entry in entries:
            if key == "bufferViews":
                entry["buffer"] = 0
                entry["byteOffset"] = bin_offset + entry.get("byteOffset", 0)
            elif key == "accessors":
                if "bufferView" in entry:
                    entry["bufferView"] += offsets["bufferViews"]
            elif key == "images" and "bufferView" in entry:
                entry["bufferView"] += offsets["bufferViews"]
            elif key == "textures":
                for field, target in [("source", "images"), ("sampler", "samplers")]:
                    if field in entry:
                        entry[field] += offsets[target]
            elif key == "materials":
                def texture_refs(value):
                    if isinstance(value, dict):
                        for name, child in value.items():
                            if name.endswith("Texture") and isinstance(child, dict) and "index" in child:
                                child["index"] += offsets["textures"]
                            else:
                                texture_refs(child)
                texture_refs(entry)
                # No flash of overlapping templates before scene-graph initialization.
                rgba = entry.setdefault("pbrMetallicRoughness", {}).setdefault("baseColorFactor", [1, 1, 1, 1])
                rgba[3] = 0
                entry["alphaMode"] = "MASK"
                entry["alphaCutoff"] = .5
            elif key == "meshes":
                for primitive in entry["primitives"]:
                    primitive["attributes"] = {name: index + offsets["accessors"] for name, index in primitive["attributes"].items()}
                    if "indices" in primitive:
                        primitive["indices"] += offsets["accessors"]
                    if "material" in primitive:
                        primitive["material"] += offsets["materials"]
            elif key == "nodes":
                if "mesh" in entry:
                    entry["mesh"] += offsets["meshes"]
                if "children" in entry:
                    entry["children"] = [i + offsets["nodes"] for i in entry["children"]]
        doc.setdefault(key, []).extend(entries)
    roots = clothes["scenes"][clothes.get("scene", 0)]["nodes"]
    doc["scenes"][doc.get("scene", 0)]["nodes"].extend(i + offsets["nodes"] for i in roots)
    doc["extensionsUsed"] = sorted(set(body.get("extensionsUsed", []) + clothes.get("extensionsUsed", [])))
    binary = body_bin + b"\0" * (bin_offset - len(body_bin)) + clothes_bin
    binary += b"\0" * (-len(binary) % 4)
    # Render the exact supplied vertices with region-specific index lists. Covered
    # body surfaces are masked, rather than poking through fitted clothing. The
    # original meshes and binary prefix remain intact and reusable in this asset.
    body_node = next(n for n in doc["nodes"] if n.get("name") == "Mannequin_Body")
    original_mesh = doc["meshes"][body_node["mesh"]]
    rendered = {"name": "Mannequin_Body_ClothingRegions", "primitives": []}
    for primitive in original_mesh["primitives"]:
        position = doc["accessors"][primitive["attributes"]["POSITION"]]
        pv = doc["bufferViews"][position["bufferView"]]
        pstart = pv.get("byteOffset", 0) + position.get("byteOffset", 0)
        stride = pv.get("byteStride", 12)
        positions = [struct.unpack_from("<fff", binary, pstart + i * stride) for i in range(position["count"])]
        accessor = doc["accessors"][primitive["indices"]]
        view = doc["bufferViews"][accessor["bufferView"]]
        fmt = {5121: "B", 5123: "H", 5125: "I"}[accessor["componentType"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        indices = struct.unpack_from("<" + fmt * accessor["count"], binary, start)
        grouped = {}
        shift = 0 if sex == "male" else -.05
        arm_boundary = .245 if sex == "male" else .200
        for i in range(0, len(indices), 3):
            triangle = indices[i:i + 3]
            x, y, z = [sum(positions[index][axis] for index in triangle) / 3 for axis in range(3)]
            if y > 1.54 + shift:
                region = "always"
            elif y > 1.06 + shift:
                region = "upperarms" if abs(x) > arm_boundary and y < 1.32 + shift else "torso"
                if region == "torso" and abs(x) < .085 and z > .02:
                    region = "chest"
            elif abs(x) > arm_boundary:
                region = "hands" if y < .970 + shift else "forearms"
            elif y > .84 + shift:
                region = "pelvis"
            elif y > .60 + shift:
                region = "thighs"
            elif y > .165:
                region = "legs"
            else:
                region = "feet"
            grouped.setdefault(region, []).extend(triangle)
        for region, values in grouped.items():
            mat = copy.deepcopy(doc["materials"][primitive["material"]])
            mat["name"] = "body:" + region
            mat_index = len(doc["materials"])
            doc["materials"].append(mat)
            payload = struct.pack("<" + "I" * len(values), *values)
            buffer_view = len(doc["bufferViews"])
            doc["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload), "target": 34963})
            binary += payload
            new_accessor = len(doc["accessors"])
            doc["accessors"].append({"bufferView": buffer_view, "componentType": 5125, "count": len(values), "type": "SCALAR"})
            part = copy.deepcopy(primitive)
            part.update(indices=new_accessor, material=mat_index)
            rendered["primitives"].append(part)
    body_node["mesh"] = len(doc["meshes"])
    doc["meshes"].append(rendered)
    briefs = next(n for n in doc["nodes"] if n.get("name") == "Mannequin_Briefs")
    for primitive in doc["meshes"][briefs["mesh"]]["primitives"]:
        mat = copy.deepcopy(doc["materials"][primitive["material"]])
        mat["name"] = "body:briefs"
        doc["materials"].append(mat)
        # Clone the briefs mesh to preserve the original document as well.
    briefs_mesh = copy.deepcopy(doc["meshes"][briefs["mesh"]])
    briefs_mesh["name"] = "Mannequin_Briefs_ClothingRegions"
    briefs_mesh["primitives"][0]["material"] = len(doc["materials"]) - 1
    briefs["mesh"] = len(doc["meshes"])
    doc["meshes"].append(briefs_mesh)
    doc["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(doc, separators=(",", ":")).encode("utf8")
    encoded += b" " * (-len(encoded) % 4)
    raw = (struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
           + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
           + struct.pack("<II", len(binary), 0x004E4942) + binary)
    target = ROOT / f"apps/mobile/assets/3d/clothing/{sex}-dressing.glb"
    target.write_bytes(raw)
    # Original body mesh/accessor/material data and its binary prefix are unchanged.
    assert doc["meshes"][:len(body["meshes"])] == body["meshes"]
    assert binary[:len(body_bin)] == body_bin
    triangles = 0
    for mesh in clothes["meshes"]:
        for primitive in mesh["primitives"]:
            triangles += clothes["accessors"][primitive["indices"]]["count"] // 3
    assert triangles < 60000
    return {"profile": sex, "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "asset": target.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw), "authored_clothing_triangles": triangles,
            "body_binary_preserved": True,
            "templates": sorted({m["name"].split(":")[1] for m in clothes["materials"]}),
            "license": "Project-authored clothing geometry and textile texture; original body supplied by user",
            "source_photo_reconstruction": False}


if __name__ == "__main__":
    report = {"models": [build(sex) for sex in ["male", "female"]]}
    (ROOT / "docs/REFERENCE_CLOTHING_ASSETS.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(json.dumps(report, indent=2))
