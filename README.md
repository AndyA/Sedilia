Ibex: ordered encoding for index
Oryx: fast encoding for object

## Conversions

|             | ⇢ Ibex/Oryx | ⇢ JSON | ⇢ JSONValue | ⇢ IbexValue |
| ----------- | ----------: | -----: | ----------: | ----------: |
| Ibex/Oryx ⇢ |           🟰 |      ✔ |           ✘ |           ✔ |
| JSON ⇢      |           ✔ |      🟰 |           ✔ |           ✔ |
| JSONValue ⇢ |           ✔ |      ✔ |           🟰 |           ✘ |
| IbexValue ⇢ |           ✔ |      ✔ |           ✘ |           🟰 |

## Thinks

- Ibex/Oryx native support for JS, Python (obv zig)
- Remove per-length offset from `IbexInt`.

## Ibex

- support for NDJSON (minor)
- ordered mode for indexes
- unbounded numeric precison / huge range (+/- 2^2^63-1)
- shadow class object representation

## Shadow Classes
