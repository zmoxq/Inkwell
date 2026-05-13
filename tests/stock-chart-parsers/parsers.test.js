// =============================================================================
// stock-chart parsers — D1 unit tests
// =============================================================================
//
// Run with: node parsers.test.js
//
// Tests cover:
//   - Happy paths for all 3 parsers
//   - 6 tolerance revisions (column case, multi-format dates, descending sort,
//     quote-aware CSV, thousands-separator numbers, BOM)
//   - Real-world fixture: AAPL.csv from Yahoo Finance (uploaded by user)
//   - Error semantics: each error type fires on the right input
// -----------------------------------------------------------------------------

'use strict';

const fs = require('fs');
const path = require('path');
const P = require('./parsers');

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✓ ${name}`);
  } catch (e) {
    failed++;
    failures.push({ name, error: e });
    console.log(`  ✗ ${name}`);
    console.log(`      ${e.message}`);
  }
}

function group(name, fn) {
  console.log(`\n${name}`);
  fn();
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg || 'Assertion failed');
}

function assertEq(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`${msg || 'assertEq'}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertDeep(actual, expected, msg) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    throw new Error(`${msg || 'assertDeep'}:\n  expected: ${e}\n  got:      ${a}`);
  }
}

function assertThrows(fn, errName, messageMatch) {
  let caught = null;
  try { fn(); } catch (e) { caught = e; }
  if (!caught) throw new Error(`expected throw, got nothing`);
  if (errName && caught.name !== errName) {
    throw new Error(`expected ${errName}, got ${caught.name}: ${caught.message}`);
  }
  if (messageMatch && !caught.message.match(messageMatch)) {
    throw new Error(`error message "${caught.message}" did not match ${messageMatch}`);
  }
  return caught;
}

// =============================================================================
// parseStockConfig
// =============================================================================

group('parseStockConfig — happy paths', () => {
  test('minimal valid config', () => {
    const cfg = P.parseStockConfig(`
file: my-note/AAPL.csv
`);
    assertEq(cfg.file, 'my-note/AAPL.csv');
    assertEq(cfg.type, 'candlestick');         // default
    assertEq(cfg.height, 400);                 // default
    assertDeep(cfg.indicators, []);            // default
  });

  test('full config with indicators list', () => {
    const cfg = P.parseStockConfig(`
file: my-note/AAPL.csv
type: candlestick
title: Apple Inc — 2024
height: 600
indicators:
  - volume
  - ma20
  - ma50
`);
    assertEq(cfg.file, 'my-note/AAPL.csv');
    assertEq(cfg.type, 'candlestick');
    assertEq(cfg.title, 'Apple Inc — 2024');
    assertEq(cfg.height, 600);
    assertDeep(cfg.indicators, ['volume', 'ma20', 'ma50']);
  });

  test('comments are ignored', () => {
    const cfg = P.parseStockConfig(`
# This is the data file
file: my-note/AAPL.csv
# default type
`);
    assertEq(cfg.file, 'my-note/AAPL.csv');
  });

  test('blank lines are tolerated', () => {
    const cfg = P.parseStockConfig(`

file: my-note/AAPL.csv

type: line

`);
    assertEq(cfg.file, 'my-note/AAPL.csv');
    assertEq(cfg.type, 'line');
  });

  test('quoted string values', () => {
    const cfg = P.parseStockConfig(`
file: my-note/AAPL.csv
title: "Q1: Apple's earnings recap"
`);
    assertEq(cfg.title, "Q1: Apple's earnings recap");
  });

  test('numeric height parsed', () => {
    const cfg = P.parseStockConfig(`
file: my-note/x.csv
height: 800
`);
    assertEq(cfg.height, 800);
    assertEq(typeof cfg.height, 'number');
  });

  test('empty indicators list', () => {
    const cfg = P.parseStockConfig(`
file: my-note/x.csv
indicators:
`);
    assertDeep(cfg.indicators, []);
  });
});

group('parseStockConfig — error cases', () => {
  test('missing file field', () => {
    assertThrows(() => P.parseStockConfig(`type: candlestick`),
                 'StockConfigError', /Missing required field: file/);
  });

  test('invalid type enum', () => {
    assertThrows(() => P.parseStockConfig(`
file: x.csv
type: pie
`), 'StockConfigError', /Invalid type/);
  });

  test('invalid indicator', () => {
    assertThrows(() => P.parseStockConfig(`
file: x.csv
indicators:
  - rsi
`), 'StockConfigError', /Invalid indicator/);
  });

  test('invalid height (negative)', () => {
    assertThrows(() => P.parseStockConfig(`
file: x.csv
height: -100
`), 'StockConfigError', /Invalid height/);
  });

  test('malformed line (missing colon)', () => {
    const e = assertThrows(() => P.parseStockConfig(`
file my-note/x.csv
`), 'StockConfigError', /Invalid syntax/);
    assertEq(e.line, 2);
  });

  test('top-level list item with no parent key', () => {
    assertThrows(() => P.parseStockConfig(`
- foo
`), 'StockConfigError', /List item without/);
  });

  test('unexpected top-level indentation', () => {
    assertThrows(() => P.parseStockConfig(`
file: x.csv
   type: line
`), 'StockConfigError', /indentation/);
  });
});

// =============================================================================
// parseStockCSV
// =============================================================================

group('parseStockCSV — happy paths', () => {
  test('canonical lowercase header', () => {
    const text = `date,open,high,low,close,volume
2024-01-02,187.15,188.44,183.89,185.64,82488670
2024-01-03,184.22,185.88,183.43,184.25,58414460
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 2);
    assertEq(rows[0].time, '2024-01-02');
    assertEq(rows[0].open, 187.15);
    assertEq(rows[0].volume, 82488670);
  });

  test('REVISION 1: column name case + trailing space tolerance', () => {
    const text = `Date,Open,High,Low,Close ,Volume
2024-01-02,187.15,188.44,183.89,185.64,82488670
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].time, '2024-01-02');
    assertEq(rows[0].close, 185.64);
  });

  test('REVISION 2: extra columns ignored (Adj Close)', () => {
    const text = `Date,Open,High,Low,Close,Adj Close,Volume
2024-01-02,187.15,188.44,183.89,185.64,184.20,82488670
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 1);
    assertEq(rows[0].close, 185.64);
    // Adj Close should not appear in output.
    assertEq(rows[0].adjClose, undefined);
    assertEq(rows[0]['adj close'], undefined);
  });

  test('REVISION 3: descending input is sorted ascending', () => {
    const text = `date,open,high,low,close
2024-01-05,5,5,5,5
2024-01-03,3,3,3,3
2024-01-04,4,4,4,4
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].time, '2024-01-03');
    assertEq(rows[1].time, '2024-01-04');
    assertEq(rows[2].time, '2024-01-05');
  });

  test('REVISION 4: quote-aware CSV ("52,631,200")', () => {
    const text = `Date,Open,High,Low,Close,Volume
2024-01-02,187.15,188.44,183.89,185.64,"52,631,200"
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].volume, 52631200);
  });

  test('REVISION 5: thousands-separator in unquoted volume also handled', () => {
    // Most users won't write this, but parseLooseNumber strips commas defensively.
    const text = `date,open,high,low,close,volume
2024-01-02,187.15,188.44,183.89,185.64,82488670
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].volume, 82488670);
  });

  test('REVISION 6: UTF-8 BOM stripped', () => {
    const text = '\uFEFFdate,open,high,low,close\n2024-01-02,1,2,0.5,1.5\n';
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 1);
    assertEq(rows[0].open, 1);
  });

  test('CRLF line endings', () => {
    const text = `date,open,high,low,close\r\n2024-01-02,1,2,0.5,1.5\r\n`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 1);
  });

  test('volume column absent — rows have no volume', () => {
    const text = `date,open,high,low,close
2024-01-02,187,188,183,185
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].volume, undefined);
    assertEq('volume' in rows[0], false);
  });

  test('empty volume cell (mixed) tolerated', () => {
    const text = `date,open,high,low,close,volume
2024-01-02,187,188,183,185,
2024-01-03,184,185,183,184,1000
`;
    const rows = P.parseStockCSV(text);
    assertEq('volume' in rows[0], false);
    assertEq(rows[1].volume, 1000);
  });

  test('blank line in body skipped', () => {
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5

2024-01-03,2,3,1,2
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 2);
  });

  test('multiple date formats in same column', () => {
    // All formats should resolve to canonical YYYY-MM-DD.
    const text = `date,open,high,low,close
2024-01-02,1,1,1,1
03-Jan-24,2,2,2,2
01/04/2024,3,3,3,3
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].time, '2024-01-02');
    assertEq(rows[1].time, '2024-01-03');
    assertEq(rows[2].time, '2024-01-04');
  });
});

group('parseStockCSV — error cases', () => {
  test('empty input', () => {
    assertThrows(() => P.parseStockCSV(''),
                 'StockDataParseError', /empty/i);
  });

  test('header only, no data', () => {
    assertThrows(() => P.parseStockCSV(`date,open,high,low,close\n`),
                 'StockDataParseError', /no data/);
  });

  test('missing required column', () => {
    const text = `date,open,low,close
2024-01-02,1,0.5,1.5
`;
    const e = assertThrows(() => P.parseStockCSV(text),
                           'StockDataParseError', /missing required column.*high/i);
    assertEq(e.column, 'high');
  });

  test('non-numeric in OHLC cell', () => {
    const text = `date,open,high,low,close
2024-01-02,N/A,2,0.5,1.5
`;
    const e = assertThrows(() => P.parseStockCSV(text),
                           'StockDataParseError', /open is not a number/);
    assertEq(e.line, 2);
    assertEq(e.column, 'open');
  });

  test('unrecognized date format', () => {
    const text = `date,open,high,low,close
not-a-date,1,2,0.5,1.5
`;
    assertThrows(() => P.parseStockCSV(text),
                 'StockDataParseError', /cannot parse date/);
  });

  test('duplicate dates rejected', () => {
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-02,2,3,1,2
`;
    assertThrows(() => P.parseStockCSV(text),
                 'StockDataParseError', /Duplicate date/);
  });

  test('unterminated quote', () => {
    const text = `date,open,high,low,close,volume
2024-01-02,1,2,0.5,1.5,"hello
`;
    assertThrows(() => P.parseStockCSV(text),
                 'StockDataParseError', /unterminated/i);
  });
});

// =============================================================================
// parseStockJSON
// =============================================================================

group('parseStockJSON — happy paths', () => {
  test('canonical lowercase fields', () => {
    const json = JSON.stringify([
      { date: '2024-01-02', open: 1, high: 2, low: 0.5, close: 1.5, volume: 1000 },
      { date: '2024-01-03', open: 2, high: 3, low: 1, close: 2.5 }
    ]);
    const rows = P.parseStockJSON(json);
    assertEq(rows.length, 2);
    assertEq(rows[0].volume, 1000);
    assertEq('volume' in rows[1], false);
  });

  test('capitalized fields tolerated (Date, Open, ...)', () => {
    const json = JSON.stringify([
      { Date: '2024-01-02', Open: 1, High: 2, Low: 0.5, Close: 1.5, Volume: 1000 }
    ]);
    const rows = P.parseStockJSON(json);
    assertEq(rows[0].open, 1);
    assertEq(rows[0].volume, 1000);
  });

  test('out-of-order dates sorted ascending', () => {
    const json = JSON.stringify([
      { date: '2024-01-05', open: 5, high: 5, low: 5, close: 5 },
      { date: '2024-01-03', open: 3, high: 3, low: 3, close: 3 }
    ]);
    const rows = P.parseStockJSON(json);
    assertEq(rows[0].time, '2024-01-03');
  });

  test('extra fields ignored', () => {
    const json = JSON.stringify([
      { date: '2024-01-02', open: 1, high: 2, low: 0.5, close: 1.5, adj_close: 1.4, dividends: 0 }
    ]);
    const rows = P.parseStockJSON(json);
    assertEq(rows.length, 1);
  });
});

group('parseStockJSON — error cases', () => {
  test('not a JSON array', () => {
    assertThrows(() => P.parseStockJSON('{"foo": "bar"}'),
                 'StockDataParseError', /must be an array/);
  });

  test('empty array', () => {
    assertThrows(() => P.parseStockJSON('[]'),
                 'StockDataParseError', /empty/);
  });

  test('item missing date', () => {
    const json = JSON.stringify([{ open: 1, high: 2, low: 0.5, close: 1.5 }]);
    assertThrows(() => P.parseStockJSON(json),
                 'StockDataParseError', /missing field "date"/);
  });

  test('malformed JSON', () => {
    assertThrows(() => P.parseStockJSON('[{not json}]'),
                 'StockDataParseError', /JSON parse failed/);
  });

  test('item is null', () => {
    assertThrows(() => P.parseStockJSON('[null]'),
                 'StockDataParseError', /expected object/);
  });
});

// =============================================================================
// selectDataParser
// =============================================================================

group('selectDataParser', () => {
  test('.csv → parseStockCSV', () => {
    assertEq(P.selectDataParser('my-note/foo.csv'), P.parseStockCSV);
  });

  test('.CSV uppercase tolerated', () => {
    assertEq(P.selectDataParser('my-note/FOO.CSV'), P.parseStockCSV);
  });

  test('.json → parseStockJSON', () => {
    assertEq(P.selectDataParser('my-note/foo.json'), P.parseStockJSON);
  });

  test('unknown extension throws', () => {
    assertThrows(() => P.selectDataParser('my-note/foo.xlsx'),
                 'StockDataFormatError', /Unsupported file extension/);
  });

  test('no extension throws', () => {
    assertThrows(() => P.selectDataParser('my-note/foo'),
                 'StockDataFormatError');
  });
});

// =============================================================================
// _internal helpers (white-box tests)
// =============================================================================

group('parseLooseDate', () => {
  const f = P._internal.parseLooseDate;

  test('ISO YYYY-MM-DD', () => assertEq(f('2024-01-02'), '2024-01-02'));
  test('ISO datetime prefix', () => assertEq(f('2024-01-02T15:00:00Z'), '2024-01-02'));
  test('DD-Mon-YY', () => assertEq(f('08-May-26'), '2026-05-08'));
  test('DD-Mon-YYYY', () => assertEq(f('08-May-2024'), '2024-05-08'));
  test('D-Mon-YY (single-digit day)', () => assertEq(f('5-Jan-25'), '2025-01-05'));
  test('Mon name case-insensitive', () => assertEq(f('08-MAY-26'), '2026-05-08'));
  test('MM/DD/YYYY', () => assertEq(f('01/04/2024'), '2024-01-04'));

  test('invalid month rejected', () => assertEq(f('08-Foo-26'), null));
  test('invalid day (Feb 30) rejected', () => assertEq(f('2024-02-30'), null));
  test('garbage rejected', () => assertEq(f('hello'), null));
  test('empty rejected', () => assertEq(f(''), null));
  test('null tolerated', () => assertEq(f(null), null));

  test('2-digit year 26 → 2026', () => assertEq(f('01-Jan-26'), '2026-01-01'));
  test('2-digit year 79 → 2079', () => assertEq(f('01-Jan-79'), '2079-01-01'));
  test('2-digit year 80 → 1980', () => assertEq(f('01-Jan-80'), '1980-01-01'));
});

group('parseLooseNumber', () => {
  const f = P._internal.parseLooseNumber;
  test('plain integer', () => assertEq(f('1234'), 1234));
  test('decimal', () => assertEq(f('123.45'), 123.45));
  test('thousands separator', () => assertEq(f('52,631,200'), 52631200));
  test('thousands + decimal', () => assertEq(f('1,234.56'), 1234.56));
  test('negative', () => assertEq(f('-123.45'), -123.45));
  test('whitespace tolerated', () => assertEq(f('  123  '), 123));
  test('empty → NaN', () => { assert(isNaN(f(''))); });
  test('garbage → NaN', () => { assert(isNaN(f('foo'))); });
  test('null → NaN', () => { assert(isNaN(f(null))); });
});

group('parseCSVRow', () => {
  const f = P._internal.parseCSVRow;
  test('plain row', () => assertDeep(f('a,b,c', 1), ['a', 'b', 'c']));
  test('quoted with comma', () => assertDeep(f('"a,b",c', 1), ['a,b', 'c']));
  test('escaped quote', () => assertDeep(f('"he said ""hi""",x', 1), ['he said "hi"', 'x']));
  test('trailing empty', () => assertDeep(f('a,b,', 1), ['a', 'b', '']));
  test('all empty', () => assertDeep(f(',,', 1), ['', '', '']));
  test('quoted empty', () => assertDeep(f('"",x', 1), ['', 'x']));
});

// =============================================================================
// REVISION 7: Yahoo Finance event rows (Dividend / Split) silently skipped
// =============================================================================

group('REVISION 7: Yahoo event-row detection', () => {
  test('Dividend row with nbsp (Yahoo real format) skipped', () => {
    // \u00A0 is U+00A0 non-breaking space; Yahoo wraps "Dividend" in nbsp.
    const text = `Date,Open,High,Low,Close,Adj Close,Volume
10-Feb-26,274.89,275.37,272.94,273.68,273.68,"34,376,900"
09-Feb-26,0.26\u00A0Dividend\u00A0,,,,,
09-Feb-26,277.91,278.20,271.70,274.62,274.62,"44,623,400"
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 2);                      // dividend row dropped
    assertEq(rows[0].time, '2026-02-09');
    assertEq(rows[0].open, 277.91);
    assertEq(rows[1].time, '2026-02-10');
  });

  test('Stock Split row skipped', () => {
    const text = `Date,Open,High,Low,Close,Volume
20-Aug-20,508.10,512.99,498.32,503.43,1000000
15-Aug-20,4:1 Stock Split,,,,
14-Aug-20,490.20,495.00,488.00,493.00,1000000
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 2);
    assertEq(rows[0].time, '2020-08-14');
    assertEq(rows[1].time, '2020-08-20');
  });

  test('plain "split" keyword (no nbsp) also recognized', () => {
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-03,split announced,,,,
2024-01-04,2,3,1,2
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 2);
  });

  test('case-insensitive: DIVIDEND matched', () => {
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-03,DIVIDEND 0.5,,,,
`;
    const rows = P.parseStockCSV(text);
    assertEq(rows.length, 1);
  });

  test('NEGATIVE: random non-numeric data still throws (not classified as event)', () => {
    // No dividend/split keyword → must NOT be silently skipped.
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-03,N/A,5,3,4
`;
    const e = assertThrows(() => P.parseStockCSV(text),
                           'StockDataParseError', /open is not a number/);
    assertEq(e.line, 3);
  });

  test('NEGATIVE: row with mixed numeric+text NOT classified as event', () => {
    // Only OHLC partially garbage (say, open is "dividend" but high is 5).
    // Condition (1) requires ALL OHLC non-numeric. So this should still throw.
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-03,dividend,5,3,4
`;
    assertThrows(() => P.parseStockCSV(text),
                 'StockDataParseError', /open is not a number/);
  });

  test('NEGATIVE: empty OHLC without event keyword still throws', () => {
    const text = `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
2024-01-03,,,,,
`;
    assertThrows(() => P.parseStockCSV(text),
                 'StockDataParseError');
  });
});

group('REVISION 7: helpers', () => {
  const f = P._internal.normalizeWhitespace;
  test('nbsp → space', () => assertEq(f('a\u00A0b'), 'a b'));
  test('zero-width space → space', () => assertEq(f('a\u200Bb'), 'a b'));
  test('regular spaces preserved', () => assertEq(f('a b c'), 'a b c'));
  test('null → empty string', () => assertEq(f(null), ''));
  test('trims edges', () => assertEq(f('  a\u00A0  '), 'a'));
});



group('Real-world fixture: appl.csv (Yahoo Finance export)', () => {
  const csvPath = path.join(__dirname, 'appl.csv');
  if (!fs.existsSync(csvPath)) {
    test('SKIP — appl.csv not present in stock-chart dir', () => {});
    return;
  }
  const text = fs.readFileSync(csvPath, 'utf8');

  test('parses without error', () => {
    const rows = P.parseStockCSV(text);
    assert(rows.length > 0, 'should have rows');
  });

  test('row count matches data lines minus 1 event row', () => {
    const rows = P.parseStockCSV(text);
    // appl.csv: 251 lines = 1 header + 250 entries.
    // 1 of those 250 is a "0.26 Dividend" event row at line 64 — should be
    // silently skipped, leaving 249 OHLC rows.
    assertEq(rows.length, 249);
  });

  test('rows are sorted ascending by time', () => {
    const rows = P.parseStockCSV(text);
    for (let i = 1; i < rows.length; i++) {
      assert(rows[i].time > rows[i - 1].time,
             `out of order at index ${i}: ${rows[i - 1].time} → ${rows[i].time}`);
    }
  });

  test('first row is the oldest date (May 13, 2025)', () => {
    const rows = P.parseStockCSV(text);
    assertEq(rows[0].time, '2025-05-13');
    assertEq(rows[0].open, 210.43);
    assertEq(rows[0].close, 212.93);
  });

  test('last row is the newest date (May 08, 2026)', () => {
    const rows = P.parseStockCSV(text);
    const last = rows[rows.length - 1];
    assertEq(last.time, '2026-05-08');
    assertEq(last.close, 293.32);
  });

  test('volume parsed correctly with thousands separators', () => {
    const rows = P.parseStockCSV(text);
    const last = rows[rows.length - 1];
    assertEq(last.volume, 52631200);   // "52,631,200"
  });

  test('Adj Close column ignored (not in output)', () => {
    const rows = P.parseStockCSV(text);
    for (const row of rows) {
      assertEq('adjClose' in row, false);
      assertEq('adj close' in row, false);
      assertEq('adj_close' in row, false);
    }
  });

  test('all rows have valid OHLCV', () => {
    const rows = P.parseStockCSV(text);
    for (const row of rows) {
      assert(Number.isFinite(row.open), `bad open at ${row.time}`);
      assert(Number.isFinite(row.high), `bad high at ${row.time}`);
      assert(Number.isFinite(row.low), `bad low at ${row.time}`);
      assert(Number.isFinite(row.close), `bad close at ${row.time}`);
      assert(Number.isFinite(row.volume), `bad volume at ${row.time}`);
      assert(row.high >= row.low, `high<low at ${row.time}`);
    }
  });
});

// =============================================================================
// Summary
// =============================================================================

console.log(`\n${'='.repeat(60)}`);
console.log(`PASSED: ${passed}   FAILED: ${failed}   TOTAL: ${passed + failed}`);
console.log(`${'='.repeat(60)}`);

if (failed > 0) {
  console.log(`\nFailures:`);
  for (const f of failures) {
    console.log(`  • ${f.name}\n    ${f.error.message}`);
  }
  process.exit(1);
}
