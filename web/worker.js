import { app, runtimeMessages } from './runtime.js';

function describe(error) {
  const detail = error?.stack || error?.message || JSON.stringify(error, Object.getOwnPropertyNames(error)) || String(error);
  return detail + '\n' + runtimeMessages.slice(-12).join('\n');
}

try {
  const initialized = await app.Initialize(new URL('./', self.location.href).href);
  if (initialized !== 'ready') throw new Error(initialized);
  self.postMessage({ type: 'ready' });
} catch (error) {
  self.postMessage({ type: 'fatal', error: describe(error) });
}

self.onmessage = ({ data }) => {
  try {
    if (data.type === 'compile') {
      const result = app.Compile(data.source, data.run);
      self.postMessage({ type: 'result', id: data.id, result, html: app.Result(result, data.stage) });
    } else if (data.type === 'stage') {
      self.postMessage({ type: 'stage', id: data.id, stage: data.stage, html: app.Result(data.result, data.stage) });
    } else if (data.type === 'example') {
      self.postMessage({ type: 'example', source: app.Example(data.name) });
    }
  } catch (error) {
    self.postMessage({ type: 'error', id: data.id, error: describe(error) });
  }
};
