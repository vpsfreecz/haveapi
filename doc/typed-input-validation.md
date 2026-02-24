# Typed input validation

## Overview
HaveAPI parameters declare a `type` (String, Text, Integer, Float, Boolean, Datetime, plus Resource).
Servers and clients MUST validate typed input parameters strictly.
Invalid values MUST NOT be silently coerced into defaults like `0`, `0.0`, or `false`.

## General rules
- Scalars only for scalar types: arrays/lists and objects/hashes are invalid for scalar types.
- `null`/`nil` means "value omitted" for validation purposes (server defaults may apply),
  but explicit `null` is still a valid value for optional parameters. Clients MUST preserve
  explicit `null` (send it as JSON `null`) so actions can distinguish "omitted" vs
  "explicitly cleared".
- Empty strings (`""` or whitespace-only strings) are invalid for Integer, Float, Boolean, and Datetime.
  For optional typed parameters (including Resource IDs), empty/whitespace is treated as
  `null`/omitted, which lets query-string inputs represent explicit `null`.
- Client-side validation is recommended; the server is authoritative.

Query-string example (explicit `null` for optional typed param):

    GET /resource/action?resource[dt]=

The empty value is treated as `null` for optional typed parameters.

## Per-type rules with examples

### Integer
Accept:
- JSON integer (e.g. `12`, `-7`)
- string matching base-10 integer `^[+-]?\d+$` after trim (e.g. `"42"`, `"+5"`)
- float that is finite and integral (e.g. `12.0`)

Reject:
- non-numeric strings (`"abc"`, `"12abc"`)
- decimal strings (`"12.0"`) and non-integral floats (`12.3`)
- empty/whitespace string

### Float
Accept:
- JSON integer or float (finite only)
- string matching a full float token after trim, including exponent (e.g. `"1e3"`, `"-0.5"`)

Reject:
- non-numeric strings
- empty/whitespace string
- non-finite values (`NaN`, `Infinity`)

Note: integers are accepted for Float and become floats.

### Boolean
Accept:
- JSON boolean
- integer `0`/`1`
- string tokens (case-insensitive, after trim):
  - truthy: `true`, `t`, `yes`, `y`, `1`
  - falsy: `false`, `f`, `no`, `n`, `0`

Reject:
- empty/whitespace string
- unknown strings (`"maybe"`)
- numbers other than 0/1

### Datetime
Accept (wire format): ISO 8601 date/datetime strings:
- `YYYY-MM-DD`
- `YYYY-MM-DDTHH:MM(:SS(.sss)?)?(Z|+HH:MM|-HH:MM|+HHMM|-HHMM)`

Examples: `"2020-01-31"`, `"2020-01-31T10:20Z"`, `"2020-01-31T10:20:30.123-0500"`.

Reject:
- empty/whitespace string
- non-ISO formats (`2020/01/01`)
- invalid calendar dates (`2020-02-30`)

Note: some clients may accept native Date/Time objects and serialize to ISO 8601.

### String / Text (rule 6.B)
Accept:
- scalar values (string, number, boolean) and coerce to string

Reject:
- arrays/lists
- objects/hashes

### Resource
Wire inputs are resource identifiers.

Accept:
- integer id
- digit-string id after trim
- (some clients) ResourceInstance -> uses its `id`
- empty/whitespace string is treated as `null`/omitted when the parameter is optional

Reject:
- empty/whitespace string for required parameters
- non-digit strings
- negative ids

If the server attempts to resolve the resource and it does not exist, it MUST become a validation error
("resource not found"), not a 500.

## Error reporting expectations
- On the server, invalid typed values are reported as parameter validation errors ("input parameters not valid").
- Clients should fail fast locally when possible and report per-parameter errors.

Recommended canonical messages used by clients:
- `not a valid integer`
- `not a valid float`
- `not a valid boolean`
- `not in ISO 8601 format`
- `not a valid string`
- `not a valid resource id`
