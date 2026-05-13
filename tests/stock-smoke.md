# Stock Chart Smoke Test

This file exercises the stock-chart extension across happy path and error scenarios.

## 1. Happy path: AAPL candlestick + volume + ma50

```stock
file: stock-smoke/appl.csv
type: candlestick
title: Apple Inc — Past Year
indicators:
  - volume
  - ma50
```

## 2. Line chart variation

```stock
file: stock-smoke/appl.csv
type: line
title: AAPL closing price
height: 300
```

## 3. With all moving averages

```stock
file: stock-smoke/appl.csv
indicators:
  - volume
  - ma20
  - ma50
  - ma200
```

## 4. Error: missing file field (config syntax error)

Should render a yellow syntax-error box:

```stock
type: candlestick
```

## 5. Error: file not in same-name subdirectory (D3 enforcement)

Should error with INVALID_FILE_PREFIX after D3 lands. Before D3, BRIDGE_NOT_READY:

```stock
file: AAPL.csv
```

## 6. Error: nonexistent file (D3-validated)

Before D3: BRIDGE_NOT_READY. After D3: FILE_NOT_FOUND:

```stock
file: stock-smoke/no-such-file.csv
```

## 7. Error: invalid type enum

```stock
file: stock-smoke/appl.csv
type: pie
```

## 8. Error: invalid indicator

```stock
file: stock-smoke/appl.csv
indicators:
  - rsi
```

## D2 baseline expectation

Before Swift `readLocalFile` handler is wired (i.e. on D2 baseline):
- Tests #1, #2, #3 will all show error: `Local file reading not yet wired (Swift bridge unavailable). This will be functional once PR 4' D3 lands.`
- Tests #4, #7, #8 will show config syntax errors (yellow) — these don't depend on D3.
- Tests #5, #6 will also show BRIDGE_NOT_READY since reading is not yet wired.

This is the expected D2 surface — D3 unblocks #1, #2, #3, #5, #6.

## D3 expectation

After D3:
- #1, #2, #3 render real charts
- #4, #7, #8 still syntax errors (D3-independent)
- #5 errors INVALID_FILE_PREFIX
- #6 errors FILE_NOT_FOUND
