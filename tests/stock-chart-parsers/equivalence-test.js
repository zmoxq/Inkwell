// Strict behavioral equivalence test.
// Strategy: rewrite the IIFE so its closures expose parsers via window.__test_extract.
// Then run all D1 test cases against both the standalone module AND the
// extracted IIFE parsers, asserting identical results.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

// Read IIFE text, inject a final line inside the closure that exposes parsers
let iifeText = fs.readFileSync(path.join(__dirname, 'stock-chart-iife.js'), 'utf8');

// Hack: replace the last "})();" with an export-then-close pattern.
// We add a window.__test_extract assignment right before the IIFE closes.
const exposeLine = `
    if (typeof window !== 'undefined') {
      window.__test_extract = {
        parseStockConfig, parseStockCSV, parseStockJSON, selectDataParser,
        StockConfigError, StockDataParseError, StockDataFormatError,
        parseLooseDate, parseLooseNumber, isYahooEventRow, normalizeWhitespace
      };
    }
`;
// Find the LAST "})();" — that's the IIFE closing
const lastCloseIdx = iifeText.lastIndexOf('})();');
if (lastCloseIdx === -1) {
  console.error('Could not find IIFE closing');
  process.exit(1);
}
iifeText = iifeText.slice(0, lastCloseIdx) + '\n' + exposeLine + '\n  ' + iifeText.slice(lastCloseIdx);

// Set up VM context with stubs
const ctx = {
  console,
  window: {
    ExtensionRegistry: {
      registerBlock() {}, registerBlockDecorator() {}, registerInline() {}
    }
  },
  document: {
    createElement: () => ({
      appendChild() {}, setAttribute() {}, classList: { add() {} },
      style: {}, dataset: {}
    })
  },
  DOMException: class extends Error { constructor(m, n) { super(m); this.name = n; } },
  ResizeObserver: class { observe() {} disconnect() {} },
  Promise, Map, Set, Date, Number, Math, JSON, RegExp, Error, parseInt, parseFloat,
  Array, Object, String,
  setTimeout, clearTimeout, queueMicrotask
};
ctx.window.inkwell = {};
ctx.webkit = undefined;
ctx.LightweightCharts = undefined;
// VM needs window.ExtensionRegistry; but the IIFE checks `typeof window.ExtensionRegistry === 'undefined'`
// — our stub provides it so the IIFE will run.

// Make 'window' available as a free variable too (the IIFE references both `window.X` and bare `X`)
ctx.ExtensionRegistry = ctx.window.ExtensionRegistry;
ctx.inkwell = ctx.window.inkwell;

vm.createContext(ctx);

try {
  vm.runInContext(iifeText, ctx);
} catch (e) {
  console.error('IIFE execution failed:', e.message);
  process.exit(1);
}

const Iife = ctx.window.__test_extract;
if (!Iife) {
  console.error('Failed to extract parsers from IIFE');
  process.exit(1);
}

// Standalone module
const Mod = require('./parsers');

// Test cases — covering each tolerance revision
const cases = [
  { name: 'simple lowercase CSV', fn: 'parseStockCSV', input: `date,open,high,low,close
2024-01-02,1,2,0.5,1.5
` },
  { name: 'Yahoo-style CSV with all 7 revisions', fn: 'parseStockCSV', input: fs.readFileSync(path.join(__dirname, 'appl.csv'), 'utf8') },
  { name: 'YAML config minimal', fn: 'parseStockConfig', input: 'file: my-note/AAPL.csv' },
  { name: 'YAML config with list', fn: 'parseStockConfig', input: `file: my-note/x.csv
type: line
indicators:
  - volume
  - ma20
` },
  { name: 'JSON simple array', fn: 'parseStockJSON', input: JSON.stringify([
    { date: '2024-01-02', open: 1, high: 2, low: 0.5, close: 1.5 }
  ]) }
];

const errorCases = [
  { name: 'YAML missing file', fn: 'parseStockConfig', input: 'type: candlestick' },
  { name: 'CSV missing column', fn: 'parseStockCSV', input: 'date,open,low,close\n2024-01-02,1,0.5,1.5\n' },
  { name: 'CSV bad date', fn: 'parseStockCSV', input: 'date,open,high,low,close\nfoo,1,2,0.5,1.5\n' },
  { name: 'JSON not array', fn: 'parseStockJSON', input: '{}' }
];

let pass = 0, fail = 0;

for (const c of cases) {
  try {
    const a = Mod[c.fn](c.input);
    const b = Iife[c.fn](c.input);
    // Compare: both should produce same result. For arrays with _skippedEventLines
    // attached, just compare the JSON.
    const aj = JSON.stringify(a);
    const bj = JSON.stringify(b);
    if (aj === bj) {
      console.log(`  ✓ ${c.name}`);
      pass++;
    } else {
      console.log(`  ✗ ${c.name}: results differ`);
      console.log(`      standalone: ${aj.slice(0, 120)}...`);
      console.log(`      iife:       ${bj.slice(0, 120)}...`);
      fail++;
    }
  } catch (e) {
    console.log(`  ✗ ${c.name}: threw ${e.message}`);
    fail++;
  }
}

for (const c of errorCases) {
  let aErr = null, bErr = null;
  try { Mod[c.fn](c.input); } catch (e) { aErr = e; }
  try { Iife[c.fn](c.input); } catch (e) { bErr = e; }
  if (!aErr || !bErr) {
    console.log(`  ✗ ${c.name}: only one threw (mod=${!!aErr}, iife=${!!bErr})`);
    fail++;
    continue;
  }
  if (aErr.name !== bErr.name) {
    console.log(`  ✗ ${c.name}: error names differ (${aErr.name} vs ${bErr.name})`);
    fail++;
    continue;
  }
  if (aErr.message !== bErr.message) {
    console.log(`  ✗ ${c.name}: messages differ:\n      ${aErr.message}\n      ${bErr.message}`);
    fail++;
    continue;
  }
  console.log(`  ✓ ${c.name} (both threw ${aErr.name})`);
  pass++;
}

console.log(`\n${pass} pass, ${fail} fail`);
if (fail > 0) process.exit(1);
