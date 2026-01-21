Ibex: ordered encoding for index
Oryx: fast encoding for object

## Conversions

|             | ⇢ Ibex/Oryx |                ⇢ JSON | ⇢ IbexValue | ⇢ zig |
| ----------- | ----------: | --------------------: | ----------: | ----: |
| Ibex/Oryx ⇢ |             |                     ✔ |           ✔ |     ✔ |
| JSON ⇢      |           ✔ |                       |           ✔ |     ✔ |
| IbexValue ⇢ |           ✔ | `IbexValue.stringify` |             |     𐄂 |
| zig ⇢       |           ✔ |                     ✔ |           𐄂 |       |

## Thinks

- WHY NOT JUST STORE JSON? (sorry for shouts)
- Ibex/Oryx native support for JS, Python (obv zig)

## Ibex

- support for NDJSON (minor)
- ordered mode for indexes
- unbounded numeric precison / huge range (+/- 2^2^63-1)
- shadow class object representation

## Shadow Classes
