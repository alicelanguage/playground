// Share each verified download between the .NET runtime and Roslyn's virtual files.
export function createAssetLoader() {
  const names = new Map();
  const assemblies = new Map();

  function configure(config) {
    for (const asset of [...config.resources.coreAssembly ?? [], ...config.resources.assembly ?? []]) {
      names.set(asset.name, asset.virtualPath ?? asset.name);
    }
  }

  async function download(type, name, uri, integrity) {
    let response;
    if (typeof DecompressionStream === 'function') {
      const compressed = new URL(uri, import.meta.url);
      compressed.pathname += '.gz';
      response = await fetch(compressed, { cache: 'force-cache' });
      if (response.status === 404) response = undefined;
    }
    response ??= await fetch(uri, { cache: 'force-cache' });
    if (!response.ok) throw new Error(`Could not load ${name}: HTTP ${response.status}`);
    let bytes = new Uint8Array(await response.arrayBuffer());
    // Some hosts decode Content-Encoding themselves; don't decompress those twice.
    if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
      const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
      bytes = new Uint8Array(await new Response(stream).arrayBuffer());
    }
    if (integrity) {
      const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
      const actual = 'sha256-' + btoa(String.fromCharCode(...digest));
      if (actual !== integrity) throw new Error(`Integrity check failed for ${name}`);
    }
    if (type === 'assembly') assemblies.set(names.get(name) ?? name, bytes);
    return new Response(bytes, { headers: { 'Content-Type': type === 'dotnetwasm' ? 'application/wasm' : 'application/octet-stream' } });
  }

  function load(type, name, uri, integrity) {
    if (type !== 'assembly' && type !== 'dotnetwasm') return null;
    return download(type, name, uri, integrity);
  }

  function installReferences(module) {
    module.FS_createPath('/', 'refs', true, true);
    for (const [name, bytes] of assemblies) module.FS_createDataFile('/refs', name, bytes, true, false, true);
    assemblies.clear();
  }

  return { configure, load, installReferences };
}
