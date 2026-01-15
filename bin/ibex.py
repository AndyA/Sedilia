i64_max = [126, 254, 254, 254, 254, 254, 254, 135]
i64_min_stored = [129, 1, 1, 1, 1, 1, 1, 120]
i64_min = [b ^ 0xFF for b in i64_min_stored]


def biggy(bytes: list[int]) -> int:
    n = 0
    for b in bytes:
        n = (n << 8) | b
    return n


print(f"i64 max: {biggy(i64_max):x}")
print(f"i64 min: {biggy(i64_min):x}")
