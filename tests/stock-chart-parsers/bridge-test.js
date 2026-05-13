// D3 bridge integration test
// Simulates the full JS → Swift → JS round-trip without needing WebKit.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

// ============================================================================
// Stub: simulate Swift inkwell handler
// ============================================================================

class FakeInkwellSwiftHandler {
  constructor() {
    this.docURL = '/Users/test/workspace/my-note.md';
    this.attachmentDir = '/Users/test/workspace/my-note';
    this.files = {};   // path → content
    this.calls = [];
    this.respondAsync = false;   // toggle to test async behavior
  }

  // Mirror of Swift's userContentController dispatch
  postMessage(jsonStr) {
    const msg = JSON.parse(jsonStr);
    this.calls.push(msg);

    if (msg.type !== 'readLocalFile') {
      // Other types are ignored by this stub
      return;
    }

    const { relativePath, requestId } = msg.data;
    const finish = (response) => {
      // Mirror of Swift's evalFileReadResponse
      if (this._jsContext) {
        this._jsContext.window.inkwell._onLocalFileResponse(requestId, response);
      }
    };

    // Mirror of InkwellFileReadResolver.resolve + file read
    const result = this._resolveAndRead(relativePath);
    if (this.respondAsync) {
      setImmediate(() => finish(result));
    } else {
      finish(result);
    }
  }

  _resolveAndRead(relativePath) {
    // Mimic InkwellFileReadResolver
    if (relativePath.startsWith('/')) {
      return { success: false, error: { code: 'INVALID_FILE_PREFIX', message: 'absolute path' } };
    }
    const docName = 'my-note';
    if (!relativePath.startsWith(docName + '/')) {
      return { success: false, error: { code: 'INVALID_FILE_PREFIX', message: 'missing docname prefix' } };
    }
    // Resolve and standardize
    const fullPath = path.posix.normalize(path.posix.join(path.dirname(this.docURL), relativePath));
    if (!fullPath.startsWith(this.attachmentDir + '/')) {
      return { success: false, error: { code: 'OUTSIDE_ATTACHMENT_DIR', message: 'path traversal' } };
    }
    if (!(fullPath in this.files)) {
      return { success: false, error: { code: 'FILE_NOT_FOUND', message: 'file not found' } };
    }
    return { success: true, content: this.files[fullPath] };
  }
}

// ============================================================================
// Stub: build JS context with the readLocalFile bridge from D3 editor.html
// ============================================================================

// Extract the relevant IIFE chunk: just the bridge setup, not the whole stock-chart IIFE.
// (We don't need lightweight-charts or rendering — only the readLocalFile bridge.)
// Easier: just write the bridge inline matching D3.

const bridgeJS = `
'use strict';
const _pendingFileReads = new Map();
let _fileRequestIdCounter = 0;
if (!window.inkwell) window.inkwell = {};
window.inkwell._onLocalFileResponse = function (requestId, response) {
  const pending = _pendingFileReads.get(requestId);
  if (!pending) return;
  _pendingFileReads.delete(requestId);
  if (response && response.success) {
    pending.resolve(response.content);
  } else {
    const err = new Error(response && response.error && response.error.message
                          ? response.error.message : 'File read failed');
    if (response && response.error && response.error.code) err.code = response.error.code;
    pending.reject(err);
  }
};
window.inkwell.readLocalFile = function (relativePath, signal) {
  return new Promise((resolve, reject) => {
    const handler = (typeof webkit !== 'undefined' &&
                    webkit.messageHandlers &&
                    webkit.messageHandlers.inkwell) || null;
    if (!handler) {
      const err = new Error('inkwell bridge unavailable');
      err.code = 'BRIDGE_NOT_READY';
      reject(err);
      return;
    }
    const requestId = 'rf-' + (++_fileRequestIdCounter) + '-' + Date.now();
    _pendingFileReads.set(requestId, { resolve, reject });
    if (signal) {
      if (signal.aborted) {
        _pendingFileReads.delete(requestId);
        reject(new DOMException('Aborted', 'AbortError'));
        return;
      }
      signal.addEventListener('abort', () => {
        if (_pendingFileReads.has(requestId)) {
          _pendingFileReads.delete(requestId);
          reject(new DOMException('Aborted', 'AbortError'));
        }
      });
    }
    try {
      handler.postMessage(JSON.stringify({
        type: 'readLocalFile',
        data: { relativePath: relativePath, requestId: requestId }
      }));
    } catch (e) {
      _pendingFileReads.delete(requestId);
      reject(e);
    }
  });
};
`;

// ============================================================================
// Run tests
// ============================================================================

function makeContext(handler) {
  const ctx = {
    console,
    window: {},
    webkit: handler ? { messageHandlers: { inkwell: handler } } : undefined,
    Promise, Map, Date,
    DOMException: class extends Error { constructor(m, n) { super(m); this.name = n; } },
    setImmediate, setTimeout, queueMicrotask
  };
  ctx.window.inkwell = {};
  vm.createContext(ctx);
  vm.runInContext(bridgeJS, ctx);
  if (handler) handler._jsContext = ctx;
  return ctx;
}

let pass = 0, fail = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    pass++;
  } catch (e) {
    console.log(`  ✗ ${name}: ${e.message}`);
    fail++;
  }
}

function assertEq(a, b, msg) {
  if (a !== b) throw new Error(`${msg||''}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}

async function run() {

  // Test 1: happy path
  await test('happy path: reads file content', async () => {
    const h = new FakeInkwellSwiftHandler();
    h.files['/Users/test/workspace/my-note/AAPL.csv'] = 'date,open\n2024-01-02,187';
    const ctx = makeContext(h);
    const content = await ctx.window.inkwell.readLocalFile('my-note/AAPL.csv');
    assertEq(content, 'date,open\n2024-01-02,187', 'content');
    assertEq(h.calls.length, 1, 'should call once');
    assertEq(h.calls[0].type, 'readLocalFile', 'message type');
  });

  // Test 2: async response
  await test('async response: works correctly', async () => {
    const h = new FakeInkwellSwiftHandler();
    h.respondAsync = true;
    h.files['/Users/test/workspace/my-note/data.csv'] = 'async data';
    const ctx = makeContext(h);
    const content = await ctx.window.inkwell.readLocalFile('my-note/data.csv');
    assertEq(content, 'async data', 'async content');
  });

  // Test 3: FILE_NOT_FOUND
  await test('FILE_NOT_FOUND: rejects with code', async () => {
    const h = new FakeInkwellSwiftHandler();
    const ctx = makeContext(h);
    try {
      await ctx.window.inkwell.readLocalFile('my-note/missing.csv');
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.code, 'FILE_NOT_FOUND', 'error code');
    }
  });

  // Test 4: INVALID_FILE_PREFIX
  await test('INVALID_FILE_PREFIX: missing docname prefix', async () => {
    const h = new FakeInkwellSwiftHandler();
    const ctx = makeContext(h);
    try {
      await ctx.window.inkwell.readLocalFile('AAPL.csv');
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.code, 'INVALID_FILE_PREFIX', 'error code');
    }
  });

  // Test 5: cross-document attempt rejected
  await test('cross-document path rejected', async () => {
    const h = new FakeInkwellSwiftHandler();
    const ctx = makeContext(h);
    try {
      await ctx.window.inkwell.readLocalFile('other-note/AAPL.csv');
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.code, 'INVALID_FILE_PREFIX', 'error code');
    }
  });

  // Test 6: path traversal blocked
  await test('OUTSIDE_ATTACHMENT_DIR: path traversal blocked', async () => {
    const h = new FakeInkwellSwiftHandler();
    const ctx = makeContext(h);
    try {
      await ctx.window.inkwell.readLocalFile('my-note/../../../etc/passwd');
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.code, 'OUTSIDE_ATTACHMENT_DIR', 'error code');
    }
  });

  // Test 7: bridge missing (no webkit)
  await test('BRIDGE_NOT_READY: when webkit absent', async () => {
    const ctx = makeContext(null);
    try {
      await ctx.window.inkwell.readLocalFile('my-note/x.csv');
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.code, 'BRIDGE_NOT_READY', 'error code');
    }
  });

  // Test 8: abort signal
  await test('AbortSignal cancels pending', async () => {
    const h = new FakeInkwellSwiftHandler();
    h.respondAsync = true;
    h.files['/Users/test/workspace/my-note/big.csv'] = 'large data';
    const ctx = makeContext(h);
    const controller = new (class { constructor() { this._listeners = []; this.aborted = false; } addEventListener(e, fn) { this._listeners.push(fn); } abort() { this.aborted = true; this._listeners.forEach(fn => fn()); } })();
    const p = ctx.window.inkwell.readLocalFile('my-note/big.csv', controller);
    controller.abort();
    try {
      await p;
      throw new Error('should have rejected');
    } catch (e) {
      assertEq(e.name, 'AbortError', 'should be AbortError');
    }
  });

  // Test 9: concurrent requests use distinct requestIds
  await test('concurrent requests distinguished by requestId', async () => {
    const h = new FakeInkwellSwiftHandler();
    h.respondAsync = true;
    h.files['/Users/test/workspace/my-note/a.csv'] = 'A';
    h.files['/Users/test/workspace/my-note/b.csv'] = 'B';
    const ctx = makeContext(h);
    const [a, b] = await Promise.all([
      ctx.window.inkwell.readLocalFile('my-note/a.csv'),
      ctx.window.inkwell.readLocalFile('my-note/b.csv')
    ]);
    assertEq(a, 'A', 'first response');
    assertEq(b, 'B', 'second response');
    // Each call had a unique requestId
    const ids = h.calls.map(c => c.data.requestId);
    assertEq(new Set(ids).size, 2, 'requestIds should be distinct');
  });

  console.log(`\n${pass} pass, ${fail} fail`);
  process.exit(fail > 0 ? 1 : 0);
}

run();
