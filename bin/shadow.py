import fileinput
import json
from dataclasses import dataclass, field
from functools import cached_property
from typing import Any, Iterable, Optional


@dataclass(kw_only=True)
class Counter:
    count: int = 0

    def inc(self) -> None:
        self.count += 1


@dataclass(frozen=True, kw_only=True)
class ShadowClass:
    keys: list[str]
    usage: Counter = field(default_factory=Counter)

    @cached_property
    def index(self) -> str:
        return {k: i for i, k in enumerate(self.keys)}


@dataclass(frozen=True, kw_only=True)
class ShadowNode:
    key: str
    parent: Optional["ShadowNode"] = None
    next: dict[str, "ShadowNode"] = field(default_factory=dict)
    clazz: list[ShadowClass] = field(default_factory=list)

    def step(self, key: str) -> "ShadowNode":
        if key not in self.next:
            self.next[key] = ShadowNode(key=key, parent=self)
        return self.next[key]

    @cached_property
    def keys(self) -> list[str]:
        if self.parent is None:
            return []
        return self.parent.keys + [self.key]

    def __str__(self) -> str:
        return "{" + ", ".join(self.keys) + "}"

    def shadow(self) -> ShadowClass:
        if len(self.clazz) == 0:
            self.clazz.append(ShadowClass(keys=self.keys))
        self.clazz[0].usage.inc()
        return self.clazz[0]

    def intern(self, keys: Iterable[str]) -> ShadowClass:
        node: ShadowNode = self
        for key in keys:
            node = node.step(key)
        return node.shadow()

    @property
    def is_leaf(self) -> bool:
        return len(self.clazz) != 0


shadow_root = ShadowNode(key="$")


def walk_object(obj: Any) -> None:
    if isinstance(obj, dict):
        shadow_root.intern(obj.keys())
        for v in obj.values():
            walk_object(v)
    elif isinstance(obj, list):
        for item in obj:
            walk_object(item)


def graph_tree(node: ShadowNode) -> None:
    # print(f"# {node}")
    for child in node.next.values():
        print(f'"{node}" -> "{child}";')
        graph_tree(child)


for line in fileinput.input():
    line = line.strip()
    if line.endswith("[") or line.startswith("]"):
        continue
    if line.endswith(","):
        line = line[:-1]

    obj = json.loads(line)
    walk_object(obj)

print("digraph G {")
graph_tree(shadow_root)
print("}")
