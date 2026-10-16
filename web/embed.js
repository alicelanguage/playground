// Turns code blocks into live Alice playgrounds for documentation pages:
//
//   <script type="module" src="https://PLAYGROUND/embed.js"></script>
//   <pre data-alice-playground data-run data-stages data-readonly data-height="260">puts "hi"</pre>
//
// Each block becomes an iframe of the playground in embed mode (its own .NET worker, nothing sent to a server).
// .NET loads only when the reader presses Run. Attributes: data-run (load and run immediately instead), data-stages (show HIR/MIR/C#/IL), data-readonly, data-height (px).
const base = new URL('./', import.meta.url);
const b64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
async function pack(text) {
  const raw = new TextEncoder().encode(text);
  if (!('CompressionStream' in window)) return 'u.' + b64(raw);
  return 'z.' + b64(new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream('deflate-raw'))).arrayBuffer()));
}
export async function mount(el) {
  const code = el.textContent.replace(/^\n/, '').replace(/\s+$/, '');
  const q = new URLSearchParams({ embed: '1' });
  for (const flag of ['run', 'stages', 'readonly']) if (el.hasAttribute('data-' + flag)) q.set(flag, '1');
  const frame = document.createElement('iframe');
  frame.src = new URL('./?' + q + '#code=' + await pack(code), base).href;
  frame.title = el.getAttribute('aria-label') ?? 'Alice playground';
  frame.loading = 'lazy';
  frame.allow = 'clipboard-write';
  const lines = code.split('\n').length;
  frame.style.cssText = `width:100%;height:${el.dataset.height ?? Math.min(520, Math.max(220, lines * 23 + 90))}px;border:1px solid #d6cbb6;border-radius:12px;background:#fffcf4`;
  el.replaceWith(frame);
  return frame;
}
for (const el of document.querySelectorAll('[data-alice-playground]')) mount(el);
