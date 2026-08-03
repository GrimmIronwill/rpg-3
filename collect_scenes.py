#!/usr/bin/env python3
"""
Извлекает дерево нод из .tscn файлов Godot 4.
Парсинг без regex для секций — построчный.
"""

import re
import argparse
from pathlib import Path


def parse_tscn(text: str) -> tuple[dict, list[dict], list[str]]:
    # Чистим
    text = text.lstrip("\ufeff")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")

    ext_resources = {}
    nodes = []
    connections = []

    current_node = None

    for line in lines:
        stripped = line.strip()

        # --- ext_resource ---
        if stripped.startswith("[ext_resource"):
            path_m = re.search(r'path="([^"]+)"', stripped)
            id_m = re.search(r'id="([^"]+)"', stripped) or re.search(r'id=(\d+)', stripped)
            if path_m and id_m:
                ext_resources[id_m.group(1)] = path_m.group(1)
            continue

        # --- node ---
        if stripped.startswith("[node"):
            # Сохраняем предыдущую ноду
            if current_node is not None:
                nodes.append(current_node)

            current_node = {
                "name": "",
                "type": "",
                "parent": "",
                "instance": "",
                "script": "",
                "groups": [],
            }

            name_m = re.search(r'name="([^"]+)"', stripped)
            type_m = re.search(r'type="([^"]+)"', stripped)
            parent_m = re.search(r'parent="([^"]*)"', stripped)
            inst_m = (
                re.search(r'instance=ExtResource$\s*"([^"]+)"\s*$', stripped)
                or re.search(r'instance=ExtResource$\s*(\d+)\s*$', stripped)
            )

            if name_m:
                current_node["name"] = name_m.group(1)
            if type_m:
                current_node["type"] = type_m.group(1)
            if parent_m:
                current_node["parent"] = parent_m.group(1)
            if inst_m:
                res_id = inst_m.group(1)
                current_node["instance"] = ext_resources.get(res_id, f"ExtResource({res_id})")
                if not current_node["type"]:
                    current_node["type"] = "(instance)"
            continue

        # --- connection ---
        if stripped.startswith("[connection"):
            # Сохраняем предыдущую ноду
            if current_node is not None:
                nodes.append(current_node)
                current_node = None

            conn_m = re.search(
                r'signal="([^"]+)"\s+from="([^"]+)"\s+to="([^"]+)"\s+method="([^"]+)"',
                stripped,
            )
            if conn_m:
                connections.append(
                    f'{conn_m.group(2)}.{conn_m.group(1)} -> {conn_m.group(3)}.{conn_m.group(4)}'
                )
            continue

        # --- Любая другая секция [ ... ] — завершаем текущую ноду ---
        if stripped.startswith("[") and not stripped.startswith("[node") and not stripped.startswith("[connection"):
            if current_node is not None:
                nodes.append(current_node)
                current_node = None
            continue

        # --- Свойства текущей ноды ---
        if current_node is not None:
            # script
            script_m = (
                re.search(r'^script\s*=\s*ExtResource$\s*"([^"]+)"\s*$', stripped)
                or re.search(r'^script\s*=\s*ExtResource$\s*(\d+)\s*$', stripped)
            )
            if script_m:
                res_id = script_m.group(1)
                current_node["script"] = ext_resources.get(res_id, f"ExtResource({res_id})")

            # groups
            groups_m = re.search(r'^groups\s*=\s*$([^$]*)$', stripped)
            if groups_m:
                current_node["groups"] = [
                    g.strip().strip('"')
                    for g in groups_m.group(1).split(",")
                    if g.strip()
                ]

    # Последняя нода
    if current_node is not None:
        nodes.append(current_node)

    return ext_resources, nodes, connections


def build_tree(nodes: list[dict], connections: list[str]) -> str:
    lines = []

    for node in nodes:
        if not node["parent"]:
            depth = 0
        elif node["parent"] == ".":
            depth = 1
        else:
            depth = node["parent"].count("/") + 2

        indent = "  " * depth
        prefix = "|- " if depth > 0 else ""

        parts = [f"{indent}{prefix}{node['name']}"]

        if node["type"]:
            parts.append(f" [{node['type']}]")
        if node["instance"]:
            parts.append(f" <- {node['instance']}")
        if node["script"]:
            parts.append(f"  # {node['script']}")
        if node["groups"]:
            parts.append(f"  groups: {node['groups']}")

        lines.append("".join(parts))

    if connections:
        lines.append("")
        lines.append("  Signals:")
        for conn in connections:
            lines.append(f"    > {conn}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Extract node trees from .tscn")
    parser.add_argument("entry_dir")
    parser.add_argument("-o", "--output", default="scenes_debug.txt")
    args = parser.parse_args()

    entry_path = Path(args.entry_dir).resolve()
    if not entry_path.is_dir():
        print(f"[ERROR] Not found: {entry_path}")
        return

    found = sorted(entry_path.rglob("*.tscn"))
    if not found:
        print(f"[INFO] No .tscn in {entry_path}")
        return

    script_dir = Path(__file__).resolve().parent
    output_path = script_dir / args.output

    ok = 0
    fail = 0

    with open(output_path, "w", encoding="utf-8") as out:
        for i, fp in enumerate(found):
            rel = fp.relative_to(entry_path)
            if i > 0:
                out.write("\n\n")
            out.write(f"{'=' * 60}\n")
            out.write(f"{rel}\n")
            out.write(f"{'=' * 60}\n")

            try:
                raw = fp.read_bytes()
                text = raw.decode("utf-8-sig", errors="replace")
                _, nodes, connections = parse_tscn(text)

                if nodes:
                    out.write(build_tree(nodes, connections) + "\n")
                    ok += 1
                else:
                    # Диагностика
                    has_node = "[node" in text
                    out.write(f"[NO NODES] contains '[node': {has_node}, file size: {len(raw)} bytes\n")
                    fail += 1
            except Exception as e:
                out.write(f"[ERROR: {e}]\n")
                fail += 1

    print(f"[DONE] OK: {ok}, fail: {fail}")
    print(f"       Output: {output_path}")


if __name__ == "__main__":
    main()
