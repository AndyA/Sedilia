Ibex: ordered encoding for index
Oryx: fast encoding for object

## Conversions

|             | ⇢ Ibex/Oryx | ⇢ JSON | ⇢ JSONValue | ⇢ IbexValue |
| ----------- | ----------: | -----: | ----------: | ----------: |
| Ibex/Oryx ⇢ |           🟰 |      ✔ |           ✘ |           ✔ |
| JSON ⇢      |           ✔ |      🟰 |           ✔ |           ✔ |
| JSONValue ⇢ |           ✔ |      ✔ |           🟰 |           ✘ |
| IbexValue ⇢ |           ✔ |      ✔ |           ✘ |           🟰 |

## TODO

- Remove per-length offset from `IbexInt`.
- Benchmark Io.Writer based encoding
- Ibex/Oryx native support for JS, Python (obv zig)

## Ibex

- support for NDJSON (minor)
- ordered mode for indexes
- unbounded numeric precison / huge range (+/- 2^2^63-1)
- shadow class object representation

## Shadow Classes
