# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///

import fileinput
import json
import re
from dataclasses import dataclass
from typing import Iterable, Iterator, Optional


@dataclass(frozen=True, kw_only=True)
class Info:
    timestamp: str
    commit: str
    host: str
    zig: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class Stage:
    index: int
    stage_name: str
    metric_name: str
    rate: int


@dataclass(frozen=True, kw_only=True)
class BenchmarkResult:
    info: Info
    stages: list[Stage]

    def flattened(self) -> list[dict[str, str | int]]:
        base = {
            "timestamp": self.info.timestamp,
            "commit": self.info.commit,
            "host": self.info.host,
        }
        if self.info.zig is not None:
            base["zig"] = self.info.zig

        results = []
        for stage in self.stages:
            entry = base.copy()
            entry.update(
                {
                    "stage_index": stage.index,
                    "stage_name": stage.stage_name,
                    "metric_name": stage.metric_name,
                    "rate": stage.rate,
                }
            )
            results.append(entry)
        return results


def load_benchmarks(lines: Iterable[str]) -> Iterator[BenchmarkResult]:
    info: Optional[Info] = None
    stages: list[Stage] = []

    for line in lines:
        line = line.strip()
        if m := re.fullmatch(r"\[\s*(\S+)\s*\]\s*(.+?):\s*(\d+)\s*\/\s*s", line):
            if info is None:
                raise ValueError("Stage found before benchmark info")
            stage_name, metric_name, rate = m.groups()
            stage = Stage(
                index=len(stages),
                stage_name=stage_name,
                metric_name=metric_name,
                rate=int(rate),
            )
            stages.append(stage)
        elif line.startswith("#"):
            continue
        else:
            if info is not None:
                yield BenchmarkResult(info=info, stages=stages)
                stages = []

            parts = re.split(r"\s+-\s+", line)
            if len(parts) < 3 or len(parts) > 4:
                print(parts)
                raise ValueError("Invalid benchmark info line")

            timestamp, commit, host = parts[:3]
            zig = parts[3] if len(parts) == 4 else None
            info = Info(timestamp=timestamp, commit=commit, host=host, zig=zig)
            stages = []

    if info is not None:
        yield BenchmarkResult(info=info, stages=stages)


for bm in load_benchmarks(fileinput.input()):
    for rec in bm.flattened():
        print(json.dumps(rec))
