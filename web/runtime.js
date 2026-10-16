// Browser bootstrap only. The application, compiler views, and rendering are Alice exports.
import { dotnet } from './_framework/dotnet.js';

export const runtimeMessages = [];
for (const level of ['error', 'warn']) {
  const original = console[level].bind(console);
  console[level] = (...args) => { runtimeMessages.push(args.map(String).join(' ')); if (runtimeMessages.length > 32) runtimeMessages.shift(); original(...args); };
}

const runtime = await dotnet.withDiagnosticTracing(false).create();
const exports = await runtime.getAssemblyExports(runtime.getConfig().mainAssemblyName);
export const app = exports.Alice.Playground.Browser;
