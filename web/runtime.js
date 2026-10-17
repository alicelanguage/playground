// Browser bootstrap only. The application, compiler views, and rendering are Alice exports.
import { dotnet } from './_framework/dotnet.js';
import { createAssetLoader } from './assets.js';

export const runtimeMessages = [];
for (const level of ['error', 'warn']) {
  const original = console[level].bind(console);
  console[level] = (...args) => { runtimeMessages.push(args.map(String).join(' ')); if (runtimeMessages.length > 32) runtimeMessages.shift(); original(...args); };
}

const assets = createAssetLoader();
const runtime = await dotnet.withDiagnosticTracing(false)
  .withOnConfigLoaded(assets.configure)
  .withResourceLoader(assets.load)
  .create();
assets.installReferences(runtime.Module);
const exports = await runtime.getAssemblyExports(runtime.getConfig().mainAssemblyName);
export const app = exports.Alice.Playground.Browser;
