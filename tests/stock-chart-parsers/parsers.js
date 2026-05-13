// =============================================================================
// stock-chart parsers — D1 deliverable, PR 4'
// =============================================================================
//
// Three independent parsers used by the stock-chart extension:
//   1. parseStockConfig  : YAML-subset → config object  (fenced block body)
//   2. parseStockCSV     : CSV → OHLCV array            (data file, .csv)
//   3. parseStockJSON    : JSON → OHLCV array           (data file, .json)
//
// Each throws a typed Error on failure. The error name is one of:
//   StockConfigError       — config parse / required fields / enum values
//   StockDataParseError    — CSV/JSON content malformed (column missing, bad number)
//   StockDataFormatError   — file extension not recognized at dispatch level
//
// All parsers normalize output to a canonical shape:
//   config: { file, type, title?, indicators[], height }
//   data:   [{ time, open, high, low, close, volume? }, ...] sorted ascending by time
//          where `time` is a string 'YYYY-MM-DD' (lightweight-charts wire format)
//
// Designed for browser & Node. No dependencies. ES2017+ syntax.
// -----------------------------------------------------------------------------

'use strict';

// -----------------------------------------------------------------------------
// Error types
// -----------------------------------------------------------------------------

class StockConfigError extends Error {
  constructor(message, opts = {}) {
    super(message);
    this.name = 'StockConfigError';
    if (opts.line != null) this.line = opts.line;
    if (opts.field != null) this.field = opts.field;
  }
}

class StockDataParseError extends Error {
  constructor(message, opts = {}) {
    super(message);
    this.name = 'StockDataParseError';
    if (opts.line != null) this.line = opts.line;
    if (opts.column != null) this.column = opts.column;
  }
}

class StockDataFormatError extends Error {
  constructor(message) {
    super(message);
    this.name = 'StockDataFormatError';
  }
}

// -----------------------------------------------------------------------------
// Shared utilities
// -----------------------------------------------------------------------------

// Strip UTF-8 BOM if present (revision 6).
function stripBOM(text) {
  if (typeof text !== 'string') return text;
  if (text.charCodeAt(0) === 0xFEFF) return text.slice(1);
  return text;
}

// Parse a number that may include thousands-separator commas: "52,631,200" → 52631200.
// Returns NaN for unparseable input — caller decides what to do.
function parseLooseNumber(s) {
  if (s == null) return NaN;
  if (typeof s === 'number') return s;
  const trimmed = String(s).trim();
  if (trimmed === '') return NaN;
  // Strip thousands-separator commas. We only do this if removing them yields
  // a parseable number — avoids destroying genuinely weird input.
  const stripped = trimmed.replace(/,/g, '');
  const n = Number(stripped);
  return Number.isFinite(n) ? n : NaN;
}

// Date parsing — accept 4 formats, return canonical 'YYYY-MM-DD' string.
// Returns null on failure.
const MONTH_ABBREV = {
  jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
  jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12'
};

function parseLooseDate(s) {
  if (s == null) return null;
  const str = String(s).trim();
  if (str === '') return null;

  // Format 1: ISO YYYY-MM-DD (also handles RFC 3339 prefix)
  let m = str.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (m) {
    const yyyy = m[1], mm = m[2], dd = m[3];
    if (isValidYMD(+yyyy, +mm, +dd)) return `${yyyy}-${mm}-${dd}`;
    return null;
  }

  // Format 3: DD-Mon-YY (08-May-26) or DD-Mon-YYYY (08-May-2026)
  m = str.match(/^(\d{1,2})-([A-Za-z]{3})-(\d{2}|\d{4})$/);
  if (m) {
    const dd = m[1].padStart(2, '0');
    const monKey = m[2].toLowerCase();
    const mm = MONTH_ABBREV[monKey];
    if (!mm) return null;
    let yyyy = m[3];
    if (yyyy.length === 2) {
      // 2-digit year: assume 20xx for 00-79, 19xx for 80-99.
      // This is a pragmatic compromise — Yahoo Finance uses 2-digit yy in DD-Mon-YY.
      const n = parseInt(yyyy, 10);
      yyyy = (n < 80 ? '20' : '19') + yyyy;
    }
    if (isValidYMD(+yyyy, +mm, +dd)) return `${yyyy}-${mm}-${dd}`;
    return null;
  }

  // Format 4: MM/DD/YYYY
  m = str.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (m) {
    const mm = m[1].padStart(2, '0');
    const dd = m[2].padStart(2, '0');
    const yyyy = m[3];
    if (isValidYMD(+yyyy, +mm, +dd)) return `${yyyy}-${mm}-${dd}`;
    return null;
  }

  return null;
}

function isValidYMD(y, m, d) {
  if (!Number.isInteger(y) || !Number.isInteger(m) || !Number.isInteger(d)) return false;
  if (y < 1900 || y > 2200) return false;
  if (m < 1 || m > 12) return false;
  if (d < 1 || d > 31) return false;
  // Construct Date and verify round-trip — catches Feb 30 etc.
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y &&
         date.getUTCMonth() === m - 1 &&
         date.getUTCDate() === d;
}

// =============================================================================
// 1. parseStockConfig — minimal YAML subset
// =============================================================================
//
// Supported syntax (intentionally limited):
//   key: value                   # string, number, or boolean
//   key:                         # followed by indented list items:
//     - item1
//     - item2
//   # comment                    # line starts with # (after optional whitespace)
//                                # trailing comments after value are NOT supported
//                                # to keep parsing predictable
//
// Returns: { file, type, title?, indicators, height }
// Throws StockConfigError with .line set to the offending 1-based line number.
// -----------------------------------------------------------------------------

const VALID_INDICATORS = ['volume', 'ma20', 'ma50', 'ma200'];
const VALID_TYPES = ['candlestick', 'line', 'area'];

function parseStockConfig(text) {
  text = stripBOM(text || '');
  const lines = text.split(/\r\n|\r|\n/);
  const result = {};

  let i = 0;
  while (i < lines.length) {
    const lineNo = i + 1;
    const raw = lines[i];
    const trimmed = raw.trim();

    // Skip blank lines and full-line comments.
    if (trimmed === '' || trimmed.startsWith('#')) { i++; continue; }

    // Top-level entries must NOT be indented.
    if (raw.length > 0 && /^\s/.test(raw)) {
      throw new StockConfigError(
        `Unexpected indentation at line ${lineNo}`,
        { line: lineNo }
      );
    }

    // List items at top level are illegal (lists must follow a key:).
    if (trimmed.startsWith('-')) {
      throw new StockConfigError(
        `List item without a parent key at line ${lineNo}`,
        { line: lineNo }
      );
    }

    // Match `key: value` or `key:` (value-less, expecting list).
    const m = trimmed.match(/^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$/);
    if (!m) {
      throw new StockConfigError(
        `Invalid syntax at line ${lineNo}: expected "key: value"`,
        { line: lineNo }
      );
    }
    const key = m[1];
    const rest = m[2];

    if (rest === '') {
      // Value-less key — collect indented list items.
      const items = [];
      i++;
      while (i < lines.length) {
        const itemRaw = lines[i];
        const itemTrim = itemRaw.trim();
        if (itemTrim === '' || itemTrim.startsWith('#')) { i++; continue; }
        // Must be indented + start with "- ".
        if (!/^\s+-\s+/.test(itemRaw) && !/^\s+-$/.test(itemRaw)) break;
        const itemMatch = itemRaw.match(/^\s+-\s+(.*)$/) || itemRaw.match(/^\s+-\s*$/);
        if (!itemMatch) break;
        const itemValue = (itemMatch[1] || '').trim();
        items.push(coerceScalar(itemValue));
        i++;
      }
      result[key] = items;
      continue;
    }

    // `key: value` — coerce value to scalar.
    result[key] = coerceScalar(rest);
    i++;
  }

  return validateConfig(result);
}

function coerceScalar(s) {
  if (s === '') return '';
  // Strip surrounding quotes if present.
  if ((s.startsWith('"') && s.endsWith('"')) ||
      (s.startsWith("'") && s.endsWith("'"))) {
    return s.slice(1, -1);
  }
  if (s === 'true') return true;
  if (s === 'false') return false;
  // Numeric? Only accept if entire string is a valid number.
  if (/^-?\d+(\.\d+)?$/.test(s)) {
    const n = Number(s);
    if (Number.isFinite(n)) return n;
  }
  return s;
}

function validateConfig(cfg) {
  // Required: file
  if (!cfg.file || typeof cfg.file !== 'string') {
    throw new StockConfigError('Missing required field: file', { field: 'file' });
  }

  // type defaults to candlestick.
  if (cfg.type == null) {
    cfg.type = 'candlestick';
  } else if (typeof cfg.type !== 'string' || !VALID_TYPES.includes(cfg.type)) {
    throw new StockConfigError(
      `Invalid type: "${cfg.type}". Must be one of: ${VALID_TYPES.join(', ')}`,
      { field: 'type' }
    );
  }

  // title is optional string.
  if (cfg.title != null && typeof cfg.title !== 'string') {
    cfg.title = String(cfg.title);
  }

  // indicators defaults to []; validate each entry.
  if (cfg.indicators == null) {
    cfg.indicators = [];
  } else if (!Array.isArray(cfg.indicators)) {
    throw new StockConfigError(
      'indicators must be a list',
      { field: 'indicators' }
    );
  } else {
    for (const ind of cfg.indicators) {
      if (typeof ind !== 'string' || !VALID_INDICATORS.includes(ind)) {
        throw new StockConfigError(
          `Invalid indicator: "${ind}". Supported: ${VALID_INDICATORS.join(', ')}`,
          { field: 'indicators' }
        );
      }
    }
  }

  // height defaults to 400, must be positive integer.
  if (cfg.height == null) {
    cfg.height = 400;
  } else if (!Number.isFinite(cfg.height) || cfg.height <= 0 || cfg.height > 10000) {
    throw new StockConfigError(
      `Invalid height: "${cfg.height}". Must be a positive number ≤ 10000.`,
      { field: 'height' }
    );
  }

  return cfg;
}

// =============================================================================
// 2. parseStockCSV — quote-aware, header-flexible CSV parser
// =============================================================================
//
// Required columns (matched by name, case-insensitive, whitespace-trimmed):
//   date, open, high, low, close
// Optional columns:
//   volume   (if absent, output rows have no volume key)
// Extra columns (e.g. "adj close") are silently ignored.
//
// Quoting: standard CSV — fields may be wrapped in "..." which allows commas
//          inside. Doubled quotes "" inside a quoted field represent a literal
//          quote character.
//
// Output rows: { time: 'YYYY-MM-DD', open, high, low, close, volume? }
// Output is sorted ascending by time (revision 3).
// -----------------------------------------------------------------------------

function parseStockCSV(text) {
  text = stripBOM(text || '');
  if (text.trim() === '') {
    throw new StockDataParseError('CSV is empty');
  }

  const lines = splitCSVLines(text);
  if (lines.length === 0) {
    throw new StockDataParseError('CSV has no rows');
  }

  // Header.
  const headerCells = parseCSVRow(lines[0], 1);
  const colIndex = {};
  headerCells.forEach((cell, idx) => {
    const norm = cell.trim().toLowerCase();
    colIndex[norm] = idx;
  });

  // Required columns.
  const required = ['date', 'open', 'high', 'low', 'close'];
  for (const col of required) {
    if (colIndex[col] == null) {
      throw new StockDataParseError(
        `CSV missing required column: "${col}". Found: ${Object.keys(colIndex).join(', ')}`,
        { line: 1, column: col }
      );
    }
  }
  const hasVolume = colIndex['volume'] != null;

  const rows = [];
  const skippedEventLines = [];   // for diagnostics; parser does not throw on these
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === '') continue;  // skip blank lines

    const lineNo = i + 1;
    const cells = parseCSVRow(line, lineNo);

    // Date.
    const dateCell = cells[colIndex['date']];
    const time = parseLooseDate(dateCell);
    if (time == null) {
      throw new StockDataParseError(
        `Line ${lineNo}: cannot parse date "${dateCell}". ` +
        `Accepted formats: YYYY-MM-DD, DD-Mon-YY, MM/DD/YYYY.`,
        { line: lineNo, column: 'date' }
      );
    }

    // Pre-check: is this a Yahoo Finance event row (Dividend / Split)?
    // Strict three-condition test — all three must hold to classify as event:
    //   (1) ALL of open/high/low/close fail to parse as a number
    //   (2) At least one cell contains 'dividend' / 'split' (case-insensitive,
    //       after normalizing non-breaking-space U+00A0 to regular space)
    //   (3) date already parsed (above)
    // If only condition (1) holds without (2), this is genuine bad data —
    // the original error is thrown so the user can locate it.
    if (isYahooEventRow(cells, colIndex)) {
      skippedEventLines.push({ line: lineNo, time });
      continue;
    }

    // OHLC.
    const row = { time };
    for (const col of ['open', 'high', 'low', 'close']) {
      const raw = cells[colIndex[col]];
      const n = parseLooseNumber(raw);
      if (!Number.isFinite(n)) {
        throw new StockDataParseError(
          `Line ${lineNo}: ${col} is not a number ("${raw}")`,
          { line: lineNo, column: col }
        );
      }
      row[col] = n;
    }

    // Volume (optional).
    if (hasVolume) {
      const raw = cells[colIndex['volume']];
      if (raw != null && raw.trim() !== '') {
        const n = parseLooseNumber(raw);
        if (!Number.isFinite(n)) {
          throw new StockDataParseError(
            `Line ${lineNo}: volume is not a number ("${raw}")`,
            { line: lineNo, column: 'volume' }
          );
        }
        row.volume = n;
      }
      // empty volume cell → just omit row.volume (don't crash)
    }

    rows.push(row);
  }

  if (rows.length === 0) {
    throw new StockDataParseError('CSV has header but no data rows');
  }

  // Sort ascending by time (revision 3 — accept descending input like Yahoo).
  rows.sort((a, b) => a.time < b.time ? -1 : a.time > b.time ? 1 : 0);

  // Sanity check: strict ascending uniqueness — duplicate dates would crash
  // lightweight-charts. We only warn-by-error on exact duplicates.
  for (let i = 1; i < rows.length; i++) {
    if (rows[i].time === rows[i - 1].time) {
      throw new StockDataParseError(
        `Duplicate date in data: ${rows[i].time}`,
        { column: 'date' }
      );
    }
  }

  return rows;
}

// Detect a Yahoo Finance event row (Dividend / Split / Stock Split).
// Yahoo embeds these as separate lines in OHLC CSV exports, e.g.:
//   09-Feb-26,0.26 Dividend ,,,,,
//   15-Aug-20,4:1 Stock Split,,,,,
// They have a valid date but garbage in OHLC columns and an event keyword.
//
// Conservative detection — all three must hold:
//   (1) ALL of open/high/low/close fail parseLooseNumber (not just some)
//   (2) At least one cell contains a known event keyword
//   (3) (Date already validated by caller before this is invoked)
//
// Whitespace normalization: Yahoo uses U+00A0 (non-breaking space) around
// keywords. We normalize to ASCII space before matching.
const YAHOO_EVENT_KEYWORDS = /\b(dividend|split)\b/i;

function normalizeWhitespace(s) {
  if (s == null) return '';
  // Replace nbsp (U+00A0) and other unicode spaces with regular space, then collapse.
  return String(s).replace(/[\u00A0\u2000-\u200B\u202F\u205F\u3000]/g, ' ').trim();
}

function isYahooEventRow(cells, colIndex) {
  // Condition (1): all OHLC must be non-numeric.
  for (const col of ['open', 'high', 'low', 'close']) {
    const raw = cells[colIndex[col]];
    // An empty/missing cell counts as "not a number" → consistent with event row.
    if (raw != null && raw !== '' && Number.isFinite(parseLooseNumber(raw))) {
      return false;
    }
  }
  // Condition (2): at least one cell contains an event keyword.
  for (const cell of cells) {
    if (cell == null) continue;
    const norm = normalizeWhitespace(cell);
    if (YAHOO_EVENT_KEYWORDS.test(norm)) {
      return true;
    }
  }
  return false;
}


// part of the field, not a line terminator. Returns array of raw line strings
// (with quoting still embedded — parseCSVRow unwraps).
function splitCSVLines(text) {
  const lines = [];
  let current = '';
  let inQuote = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') {
      // Toggle quote state, but track doubled "" as literal.
      if (inQuote && text[i + 1] === '"') {
        current += '""';  // keep doubled — parseCSVRow handles
        i++;
      } else {
        current += '"';
        inQuote = !inQuote;
      }
      continue;
    }
    if (!inQuote && (ch === '\n' || ch === '\r')) {
      // Handle CRLF: if \r\n, skip the \n.
      if (ch === '\r' && text[i + 1] === '\n') i++;
      lines.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  if (current !== '') lines.push(current);
  return lines;
}

// Parse a single CSV row into cell strings. Handles "...", "" (escaped quote).
function parseCSVRow(line, lineNo) {
  const cells = [];
  let cur = '';
  let inQuote = false;
  let i = 0;
  while (i < line.length) {
    const ch = line[i];
    if (inQuote) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          cur += '"';
          i += 2;
          continue;
        }
        inQuote = false;
        i++;
        continue;
      }
      cur += ch;
      i++;
      continue;
    }
    // Not in quote.
    if (ch === '"') {
      // Quote at start of field.
      if (cur === '') {
        inQuote = true;
        i++;
        continue;
      }
      // Quote mid-field is technically malformed but we accept it as literal.
      cur += ch;
      i++;
      continue;
    }
    if (ch === ',') {
      cells.push(cur);
      cur = '';
      i++;
      continue;
    }
    cur += ch;
    i++;
  }
  if (inQuote) {
    throw new StockDataParseError(
      `Line ${lineNo}: unterminated quoted field`,
      { line: lineNo }
    );
  }
  cells.push(cur);
  return cells;
}

// =============================================================================
// 3. parseStockJSON — array-of-objects validator
// =============================================================================
//
// Input must be a JSON array. Each object must have at least: date, open,
// high, low, close. Optional: volume. Extra fields ignored.
// Date strings go through the same loose date parser as CSV.
// Output sorted ascending by time, same canonical shape as CSV output.
// -----------------------------------------------------------------------------

function parseStockJSON(text) {
  text = stripBOM(text || '');
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    throw new StockDataParseError(`JSON parse failed: ${e.message}`);
  }
  if (!Array.isArray(raw)) {
    throw new StockDataParseError('JSON root must be an array of OHLCV objects');
  }
  if (raw.length === 0) {
    throw new StockDataParseError('JSON array is empty');
  }

  const rows = [];
  raw.forEach((obj, idx) => {
    const itemNo = idx + 1;  // user-facing 1-based
    if (obj == null || typeof obj !== 'object' || Array.isArray(obj)) {
      throw new StockDataParseError(
        `Item ${itemNo}: expected object, got ${Array.isArray(obj) ? 'array' : typeof obj}`
      );
    }

    // Find date field — accept "date" or "Date".
    const dateRaw = obj.date != null ? obj.date :
                    obj.Date != null ? obj.Date : null;
    if (dateRaw == null) {
      throw new StockDataParseError(`Item ${itemNo}: missing field "date"`);
    }
    const time = parseLooseDate(dateRaw);
    if (time == null) {
      throw new StockDataParseError(
        `Item ${itemNo}: cannot parse date "${dateRaw}"`
      );
    }

    const row = { time };
    for (const col of ['open', 'high', 'low', 'close']) {
      // Accept lowercase or capitalized.
      let v = obj[col];
      if (v == null) v = obj[col[0].toUpperCase() + col.slice(1)];
      if (v == null) {
        throw new StockDataParseError(`Item ${itemNo}: missing field "${col}"`);
      }
      const n = parseLooseNumber(v);
      if (!Number.isFinite(n)) {
        throw new StockDataParseError(
          `Item ${itemNo}: ${col} is not a number ("${v}")`
        );
      }
      row[col] = n;
    }

    // Volume optional.
    let v = obj.volume;
    if (v == null) v = obj.Volume;
    if (v != null && v !== '') {
      const n = parseLooseNumber(v);
      if (!Number.isFinite(n)) {
        throw new StockDataParseError(
          `Item ${itemNo}: volume is not a number ("${v}")`
        );
      }
      row.volume = n;
    }

    rows.push(row);
  });

  rows.sort((a, b) => a.time < b.time ? -1 : a.time > b.time ? 1 : 0);

  for (let i = 1; i < rows.length; i++) {
    if (rows[i].time === rows[i - 1].time) {
      throw new StockDataParseError(`Duplicate date in data: ${rows[i].time}`);
    }
  }

  return rows;
}

// =============================================================================
// Dispatcher
// =============================================================================

function selectDataParser(filePath) {
  if (typeof filePath !== 'string') {
    throw new StockDataFormatError('file path must be a string');
  }
  const lower = filePath.toLowerCase();
  if (lower.endsWith('.csv')) return parseStockCSV;
  if (lower.endsWith('.json')) return parseStockJSON;
  throw new StockDataFormatError(
    `Unsupported file extension: "${filePath}". Expected .csv or .json.`
  );
}

// =============================================================================
// Exports — supports both CommonJS (Node tests) and browser global.
// =============================================================================

const exportsObject = {
  parseStockConfig,
  parseStockCSV,
  parseStockJSON,
  selectDataParser,
  StockConfigError,
  StockDataParseError,
  StockDataFormatError,
  // Exposed for tests only:
  _internal: {
    parseLooseDate,
    parseLooseNumber,
    splitCSVLines,
    parseCSVRow,
    stripBOM,
    isYahooEventRow,
    normalizeWhitespace
  }
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = exportsObject;
}
if (typeof window !== 'undefined') {
  window.StockChartParsers = exportsObject;
}
