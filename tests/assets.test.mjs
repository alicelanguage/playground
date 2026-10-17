import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { createAssetLoader } from '../web/assets.js';

const bytes = Buffer.from('MZ managed assembly fixture');
const integrity = 'sha256-' + createHash('sha256').update(bytes).digest('base64');
const uri = 'https://playground.example/_framework/Example.fingerprint.dll';

for (const mode of ['gzip', 'host-decoded', 'missing-gzip']) {
  test(`runtime and compiler share one verified assembly (${mode})`, async t => {
    const requests = [];
    t.mock.method(globalThis, 'fetch', async (url, options) => {
      requests.push(String(url));
      assert.equal(options.cache, 'force-cache');
      if (String(url).endsWith('.gz') && mode === 'missing-gzip') return new Response(null, { status: 404 });
      return new Response(mode === 'gzip' ? gzipSync(bytes) : bytes);
    });
    const loader = createAssetLoader();
    loader.configure({ resources: { assembly: [{ name: 'Example.fingerprint.dll', virtualPath: 'Example.dll' }] } });
    const response = await loader.load('assembly', 'Example.fingerprint.dll', uri, integrity);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
    assert.deepEqual(requests, mode === 'missing-gzip' ? [uri + '.gz', uri] : [uri + '.gz']);
    const files = [];
    loader.installReferences({
      FS_createPath: (parent, name) => assert.equal(parent + name, '/refs'),
      FS_createDataFile: (directory, name, data) => files.push({ directory, name, data: Buffer.from(data) }),
    });
    assert.deepEqual(files, [{ directory: '/refs', name: 'Example.dll', data: bytes }]);
  });
}

test('corrupt compressed assets fail the boot manifest integrity check', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response(gzipSync(Buffer.from('modified DLL'))));
  const loader = createAssetLoader();
  await assert.rejects(loader.load('assembly', 'Example.dll', uri, integrity), /Integrity check failed/);
});

test('browsers without decompression fetch the original verified asset', async t => {
  const original = globalThis.DecompressionStream;
  t.after(() => { globalThis.DecompressionStream = original; });
  globalThis.DecompressionStream = undefined;
  t.mock.method(globalThis, 'fetch', async url => {
    assert.equal(String(url), uri);
    return new Response(bytes);
  });
  const response = await createAssetLoader().load('assembly', 'Example.dll', uri, integrity);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
});

test('the loader keeps WebAssembly streaming MIME and leaves JS modules to .NET', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response(gzipSync(bytes)));
  const loader = createAssetLoader();
  const response = await loader.load('dotnetwasm', 'runtime.wasm', uri, integrity);
  assert.equal(response.headers.get('content-type'), 'application/wasm');
  assert.equal(loader.load('dotnetjs', 'dotnet.native.js', uri, integrity), null);
});

test('failed downloads report their status without installing an assembly', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response(null, { status: 503 }));
  await assert.rejects(createAssetLoader().load('assembly', 'Example.dll', uri, integrity), /HTTP 503/);
});
