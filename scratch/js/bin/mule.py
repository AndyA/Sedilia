#!/usr/bin/env python3

import json
import math
import time
from datetime import datetime

with open("../../tmp/mcc.json", "r") as f:
    data = json.load(f)

rows = []


def emit(key, value):
    rows.append({"key": key, "value": value})


def view_map(doc: dict):
    if mcc := doc.get("mcc_cdc"):
        source: str = (
            doc["contentType"]["source"] if "contentType" in doc else "tagging"
        )
        emit(
            [
                datetime.fromtimestamp(mcc["sequence"]).isoformat(),
                mcc["sequence"],
                mcc["update_type"],
                mcc["object_type"],
                source,
            ],
            1,
        )


TOTAL = 12339702
scale = math.ceil(TOTAL / len(data))

print(f"Processing {len(data)} rows {scale} times each")
start = time.time()
for i in range(scale):
    for row in data:
        view_map(row)
duration = (time.time() - start) * 1000
print(f"Emitted {len(rows)} rows in {duration:.0f}ms")
