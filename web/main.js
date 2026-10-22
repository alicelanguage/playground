// DOM events, editor ergonomics and worker transport. All page HTML and compiler results are produced by Alice.
import { fitEmbed } from './embed.js';
const $ = id => document.getElementById(id);
const source = $('source');
const highlight = document.querySelector('#highlight code');
let worker;
let ready = false;
let busy = false;
let lastResult = '';
let stage = 'csharp';
let request = 0;
let timer;
let started = 0;
let badLines = new Set();
// ?embed=1 renders a docs code box: &run=1 runs on load, &stages=1 shows HIR/MIR/C#/IL, &readonly=1 locks the source.
const params = new URLSearchParams(location.search);
const embed = params.get('embed') === '1';
if (embed) {
  document.body.classList.add('embed');
  fitEmbed();
  if (params.get('stages') === '1') document.body.classList.add('stages');
  if (params.get('readonly') === '1') source.readOnly = true;
}

// ---- syntax highlighting (mirrors the CLI REPL's highlighter) ----
const KEYWORDS = new Set(('def class module struct enum interface record lib fun if elsif else unless while until for in do end case when then ' +
  'begin rescue ensure return break next yield self super and or not require using include extend getter setter property ' +
  'spawn async await val var own par unchecked raise loop lambda proc describe context it expect macro static private protected public abstract').split(' '));
const CONSTANTS = new Set(['nil', 'true', 'false']);
const esc = s => s.replace(/[&<>]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const span = (cls, text) => `<span class="t-${cls}">${esc(text)}</span>`;

function highlightLine(line) {
  let out = '';
  let i = 0;
  let prev = '';
  while (i < line.length) {
    const c = line[i];
    const rest = line.slice(i);
    let m;
    if (c === '#') { out += span('com', rest); break; }
    if (c === '"' || c === "'") {
      let j = i + 1;
      let html = '';
      let chunk = c;
      while (j < line.length) {
        if (line[j] === '\\') { chunk += line.slice(j, j + 2); j += 2; continue; }
        if (c === '"' && line[j] === '#' && line[j + 1] === '{') {
          let depth = 1, k = j + 2;
          while (k < line.length && depth > 0) { if (line[k] === '{') depth++; else if (line[k] === '}') depth--; k++; }
          html += span('str', chunk) + span('sym', '#{') + highlightLine(line.slice(j + 2, depth === 0 ? k - 1 : k)) + (depth === 0 ? span('sym', '}') : '');
          chunk = '';
          j = k;
          continue;
        }
        chunk += line[j];
        if (line[j++] === c) break;
      }
      out += html + span('str', chunk);
      i = j; prev = '';
      continue;
    }
    if (c === ':' && (m = /^:[A-Za-z_]\w*[?!]?/.exec(rest)) && !/[\w:]/.test(line[i - 1] ?? '') && !(line[i - 1] === ' ' && /[A-Z]/.test(line[i + 1]))) {
      out += span('sym', m[0]); i += m[0].length; continue;
    }
    if (c === '@' && (m = /^@@?[A-Za-z_]\w*/.exec(rest))) { out += span('ivar', m[0]); i += m[0].length; continue; }
    if (/\d/.test(c) && !/[\w]/.test(line[i - 1] ?? '') && (m = /^(0x[\da-fA-F_]+|0b[01_]+|\d[\d_]*(\.\d[\d_]*)?([eE][+-]?\d+)?)(_?[iuf](8|16|32|64))?/.exec(rest))) {
      out += span('num', m[0]); i += m[0].length; continue;
    }
    if ((m = /^[A-Za-z_]\w*[?!]?/.exec(rest))) {
      const w = m[0];
      const next = line[i + w.length];
      const cls = KEYWORDS.has(w) ? 'kw' : CONSTANTS.has(w) ? 'const' : /^[A-Z]/.test(w) ? 'ty' : (prev === 'def' || next === '(') ? 'fn' : '';
      out += cls ? span(cls, w) : esc(w);
      i += w.length;
      if (!(prev === 'def' && w === 'self' && next === '.')) prev = w;
      else { out += '.'; i++; }
      continue;
    }
    if (!/\s/.test(c)) prev = '';
    out += esc(c);
    i++;
  }
  return out;
}

function paint() {
  const lines = source.value.split('\n');
  // a trailing newline keeps the overlay as tall as the textarea's last empty line
  highlight.innerHTML = lines.map(highlightLine).join('\n') + '\n';
  const current = source.value.slice(0, source.selectionStart).split('\n').length;
  $('gutter').innerHTML = lines.map((_, i) => `<span class="ln${i + 1 === current ? ' current' : ''}${badLines.has(i + 1) ? ' bad' : ''}">${i + 1}</span>`).join('');
  sync();
}
function sync() {
  highlight.style.transform = `translate(${-source.scrollLeft}px, ${-source.scrollTop}px)`;
  $('gutter').scrollTop = source.scrollTop;
}

// ---- runtime ----
function status(text, state = '') {
  $('status').textContent = text;
  $('runtime-state').dataset.state = state;
}
// Embeds load .NET lazily: Run stays enabled before the runtime exists and starts it on click.
const lazy = () => embed && !worker;
function controls() {
  $('compile').disabled = busy || (!ready && !lazy());
  $('run').disabled = busy || (!ready && !lazy());
  $('examples').disabled = busy || !ready;
  $('stop').disabled = !busy;
}
function finish() {
  clearTimeout(timer);
  busy = false;
  controls();
}
function stop(message) {
  worker?.terminate();
  worker = undefined;
  ready = false;
  finish();
  $('compile').disabled = false;
  $('run').disabled = false;
  $('notice').textContent = message;
  $('timing').textContent = '';
  status('Stopped · Run or Compile to restart .NET');
}
function markDiagnostics() {
  badLines = new Set(Array.from(document.querySelectorAll('#result .diagnostic[data-line]'), d => Number(d.dataset.line)));
  paint();
}
function start(afterReady) {
  status('Loading .NET WebAssembly…');
  worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
  const current = worker;
  timer = setTimeout(() => stop('Runtime loading timed out. Run or Compile to retry.'), 120000);
  worker.onerror = event => {
    if (worker !== current) return;
    stop('Could not start .NET. ' + event.message);
    status('Runtime error', 'error');
  };
  worker.onmessage = ({ data }) => {
    if (worker !== current) return;
    if (data.type === 'ready') {
      clearTimeout(timer);
      ready = true;
      status('.NET WebAssembly · Ready', 'ready');
      controls();
      afterReady?.();
    } else if (data.type === 'result' && data.id === request) {
      finish();
      lastResult = data.result;
      $('result').innerHTML = data.html;
      $('timing').textContent = `${Math.round(performance.now() - started)} ms`;
      markDiagnostics();
      status('.NET WebAssembly · Ready', 'ready');
      // A stage may have been selected while compilation was in flight.
      worker.postMessage({ type: 'stage', id: request, result: lastResult, stage });
    } else if (data.type === 'stage' && data.id === request && data.stage === stage) {
      $('result').innerHTML = data.html;
      markDiagnostics();
    } else if (data.type === 'example') {
      source.value = data.source;
      edited();
      compile(false);
    } else if (data.type === 'fatal' || data.type === 'error') {
      stop(data.error);
      status('Runtime error', 'error');
    }
  };
}
function compile(run) {
  if (busy) return;
  $('notice').textContent = '';
  if (!ready) {
    busy = true;
    controls();
    start(() => { busy = false; compile(run); });
    return;
  }
  busy = true;
  controls();
  status(run ? 'Compiling & running…' : 'Compiling…');
  $('timing').textContent = '…';
  const id = ++request;
  started = performance.now();
  timer = setTimeout(() => stop('Stopped after 15 seconds. Your source is still in the editor.'), 15000);
  worker.postMessage({ type: 'compile', id, source: source.value, run, stage });
}

// ---- editor ----
function position() {
  const preceding = source.value.slice(0, source.selectionStart).split('\n');
  $('cursor').textContent = `Ln ${preceding.length}, Col ${preceding.at(-1).length + 1}`;
  paint();
}
function edited() {
  badLines = new Set();
  position();
  if (!embed) try { localStorage.setItem('alice.playground.source', source.value); } catch { /* Private storage is optional. */ }
  if (lastResult) $('notice').textContent = 'Source changed. Compile to update the results.';
}
// Inserting through execCommand keeps the browser's undo history; setRangeText is the fallback.
function insert(text, start = source.selectionStart, end = source.selectionEnd) {
  source.setSelectionRange(start, end);
  if (!document.execCommand?.('insertText', false, text)) source.setRangeText(text, start, end, 'end');
  edited();
}
function selectedLines() {
  const v = source.value;
  const from = v.lastIndexOf('\n', source.selectionStart - 1) + 1;
  let to = v.indexOf('\n', source.selectionEnd - (source.selectionEnd > source.selectionStart && v[source.selectionEnd - 1] === '\n' ? 1 : 0));
  if (to < 0) to = v.length;
  return { from, to, lines: v.slice(from, to).split('\n') };
}
function replaceLines(map) {
  const { from, to, lines } = selectedLines();
  const next = lines.map(map).join('\n');
  insert(next, from, to);
  source.setSelectionRange(from, from + next.length);
}
const OPENER = /^\s*(def|class|module|struct|enum|interface|record|if|unless|while|until|for|case|begin|describe|context|it|lib)\b(?!.*\bend\s*$)|\bdo(\s*\|[^|]*\|)?\s*$|[{[(]\s*$/;

// ---- autocomplete: keywords, Prelude and .NET names, identifiers already in the program ----
const PRELUDE = ('puts print p pp gets require sleep spawn raise loop lambda proc par_map each map select reject filter reduce sum min max ' +
  'times upto downto step each_with_index each_slice zip flat_map group_by sort_by min_by max_by count any? all? none? include? ' +
  'first last take drop sort reverse uniq compact join split strip chomp upcase downcase capitalize size length empty? to_s to_i to_f to_a ' +
  'starts_with? ends_with? gsub sub index push pop shift unshift keys values fetch has_key? delete is_a? respond_to? send not_nil! wait').split(' ');
const TYPES = ['Int32', 'Int64', 'Float64', 'Float32', 'Bool', 'String', 'Char', 'Array', 'List', 'Hash', 'Dictionary', 'HashSet', 'Math', 'Console',
  'File', 'Path', 'DateTime', 'TimeSpan', 'Guid', 'Task', 'Channel', 'Actor', 'Par', 'Simd', 'StringBuilder', 'Object'];
const MEMBERS = { Math: 'Sqrt Abs Pow Sin Cos Tan Floor Ceiling Round Max Min Log Exp PI E Clamp'.split(' '), Console: 'WriteLine Write ReadLine'.split(' '),
  File: 'ReadAllText WriteAllText Exists ReadAllLines AppendAllText Delete'.split(' '), DateTime: 'Now UtcNow Today Parse'.split(' '),
  String: 'Join Concat IsNullOrEmpty Format'.split(' '), Guid: ['NewGuid'], Path: 'Combine GetFileName GetExtension GetDirectoryName'.split(' ') };
const box = $('complete');
let items = [];
let chosen = 0;
let wordStart = 0;
function closeComplete() { box.hidden = true; items = []; }
function suggest(force) {
  const caret = source.selectionStart;
  const before = source.value.slice(0, caret);
  const m = /([A-Za-z_][\w]*\.)?([A-Za-z_@][\w]*[?!]?)?$/.exec(before);
  const owner = m?.[1]?.slice(0, -1);
  const word = m?.[2] ?? '';
  if (/#[^{]*$/.test(before.slice(before.lastIndexOf('\n') + 1)) || (!force && word.length < 2 && !owner)) return closeComplete();
  wordStart = caret - word.length;
  let pool;
  if (owner) pool = (MEMBERS[owner] ?? PRELUDE).map(n => [n, owner in MEMBERS ? owner : 'method']);
  else {
    const local = new Set(source.value.match(/\b[A-Za-z_]\w*[?!]?/g) ?? []);
    pool = [...[...KEYWORDS].map(k => [k, 'keyword']), ...TYPES.map(t => [t, 'type']), ...PRELUDE.map(n => [n, 'prelude']),
      ...[...local].filter(n => !KEYWORDS.has(n)).map(n => [n, 'local'])];
  }
  const seen = new Set();
  items = pool.filter(([n]) => n.startsWith(word) && n !== word && !seen.has(n) && seen.add(n))
    .sort((a, b) => (a[1] === 'local' ? -1 : 0) - (b[1] === 'local' ? -1 : 0) || a[0].length - b[0].length).slice(0, 40);
  if (!items.length) return closeComplete();
  chosen = 0;
  renderComplete();
  const line = before.split('\n');
  const probe = renderComplete.width ??= (() => { const c = document.createElement('canvas').getContext('2d'); c.font = getComputedStyle(source).font; return c.measureText('0').width; })();
  const lh = parseFloat(getComputedStyle(source).lineHeight);
  box.style.left = `${Math.max(4, 22 + (line.at(-1).length - word.length) * probe - source.scrollLeft)}px`;
  box.style.top = `${20 + line.length * lh - source.scrollTop + 2}px`;
  box.hidden = false;
}
function renderComplete() {
  box.innerHTML = items.map(([n, kind], i) => `<li role="option" data-i="${i}" aria-selected="${i === chosen}">${esc(n)}<small>${kind}</small></li>`).join('');
  box.children[chosen]?.scrollIntoView({ block: 'nearest' });
}
function accept() {
  const [name] = items[chosen];
  closeComplete();
  insert(name, wordStart, source.selectionStart);
}
box.addEventListener('mousedown', event => {
  const li = event.target.closest('li');
  if (!li) return;
  event.preventDefault();
  chosen = Number(li.dataset.i);
  accept();
});
source.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.code === 'Space') { event.preventDefault(); suggest(true); return; }
  if (box.hidden) return;
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    chosen = (chosen + (event.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length;
    renderComplete();
  } else if ((event.key === 'Tab' || event.key === 'Enter') && !event.shiftKey && !event.ctrlKey && !event.metaKey) {
    event.preventDefault();
    event.stopImmediatePropagation();
    accept();
  } else if (event.key === 'Escape') {
    event.preventDefault();
    event.stopImmediatePropagation();
    closeComplete();
  }
}, true);
source.addEventListener('input', event => { if (event.inputType === 'insertText' && /[\w.?!@]/.test(event.data ?? '')) suggest(false); else closeComplete(); });
source.addEventListener('blur', () => setTimeout(closeComplete, 120));
source.addEventListener('click', closeComplete);
source.addEventListener('scroll', closeComplete);

source.addEventListener('keydown', event => {
  const mod = event.ctrlKey || event.metaKey;
  if (event.key === 'Tab') {
    event.preventDefault();
    const multi = source.value.slice(source.selectionStart, source.selectionEnd).includes('\n');
    if (event.shiftKey) replaceLines(l => l.replace(/^ {1,2}/, ''));
    else if (multi) replaceLines(l => '  ' + l);
    else insert('  ');
  } else if (event.key === 'Enter' && !mod && !event.shiftKey && !event.altKey) {
    event.preventDefault();
    const line = source.value.slice(source.value.lastIndexOf('\n', source.selectionStart - 1) + 1, source.selectionStart);
    const indent = /^\s*/.exec(line)[0] + (OPENER.test(line) ? '  ' : '');
    insert('\n' + indent);
  } else if (mod && event.key === '/') {
    event.preventDefault();
    const { lines } = selectedLines();
    const commented = lines.filter(l => l.trim()).every(l => /^\s*# ?/.test(l));
    replaceLines(l => !l.trim() ? l : commented ? l.replace(/^(\s*)# ?/, '$1') : l.replace(/^(\s*)/, '$1# '));
  } else if (event.key === 'Backspace' && source.selectionStart === source.selectionEnd) {
    const before = source.value.slice(source.value.lastIndexOf('\n', source.selectionStart - 1) + 1, source.selectionStart);
    if (before.length >= 2 && /^ +$/.test(before) && before.length % 2 === 0) {
      event.preventDefault();
      insert('', source.selectionStart - 2, source.selectionStart);
    }
  }
});
// Typing a closing keyword dedents it to its block's level.
source.addEventListener('input', event => {
  if (event.inputType !== 'insertText') return;
  const start = source.value.lastIndexOf('\n', source.selectionStart - 1) + 1;
  const line = source.value.slice(start, source.selectionStart);
  if (/^ {2,}(end|else|elsif|rescue|ensure|when)$/.test(line) && !/\S/.test(source.value.slice(source.selectionStart, source.value.indexOf('\n', source.selectionStart) >>> 0))) {
    const caret = source.selectionStart;
    source.setRangeText('', start, start + 2, 'preserve');
    source.setSelectionRange(caret - 2, caret - 2);
  }
});
source.addEventListener('input', edited);
source.addEventListener('click', position);
source.addEventListener('keyup', position);
source.addEventListener('select', position);
source.addEventListener('scroll', sync);

document.addEventListener('keydown', event => {
  if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
    event.preventDefault();
    compile(true);
  } else if (event.shiftKey && event.key === 'Enter' && document.activeElement === source) {
    event.preventDefault();
    compile(false);
  } else if (event.key === 'Escape' && busy) {
    stop('Program stopped. Your source is still in the editor.');
  }
});

// ---- share / download / install ----
function toast(text) {
  const t = $('toast');
  t.textContent = text;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 2200);
}
async function copy(text, done) {
  try { await navigator.clipboard.writeText(text); toast(done); }
  catch { window.prompt('Copy this:', text); }
}
const b64 = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64 = text => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
async function pack(text) {
  const raw = new TextEncoder().encode(text);
  if (!('CompressionStream' in window)) return 'u.' + b64(raw);
  const zipped = new Uint8Array(await new Response(new Blob([raw]).stream().pipeThrough(new CompressionStream('deflate-raw'))).arrayBuffer());
  return 'z.' + b64(zipped);
}
async function unpack(token) {
  const [kind, data] = [token.slice(0, 2), token.slice(2)];
  const bytes = unb64(data);
  if (kind === 'u.') return new TextDecoder().decode(bytes);
  return await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).text();
}
$('share').onclick = async () => {
  const url = new URL(location.href);
  url.hash = 'code=' + await pack(source.value);
  history.replaceState(null, '', url);
  copy(url.href, 'Link copied — anyone with it sees this program.');
};
$('download').onclick = () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([source.value], { type: 'text/plain' }));
  a.download = 'main.al';
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
};
const INSTALL = {
  unix: ['$', 'curl -fsSL https://alice-lang.org/install.sh | sh'],
  windows: ['PS>', 'irm https://alice-lang.org/install.ps1 | iex'],
};
function chooseInstall(os) {
  document.querySelectorAll('[data-install]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.install === os)));
  [$('install-prompt').textContent, $('install-command').textContent] = INSTALL[os];
}
document.querySelectorAll('[data-install]').forEach(b => { b.onclick = () => chooseInstall(b.dataset.install); });
if (/win/i.test(navigator.userAgentData?.platform ?? navigator.platform ?? '')) chooseInstall('windows');
$('copy-install').onclick = () => copy($('install-command').textContent, 'Install command copied.');
$('shortcuts').onclick = () => $('keys').showModal();

$('run').onclick = () => compile(true);
$('compile').onclick = () => compile(false);
$('stop').onclick = () => stop('Program stopped. Your source is still in the editor.');
$('examples').onchange = () => worker?.postMessage({ type: 'example', name: $('examples').value });
document.querySelectorAll('[data-stage]').forEach(button => {
  button.onclick = () => {
    stage = button.dataset.stage;
    document.querySelectorAll('[data-stage]').forEach(tab => tab.setAttribute('aria-selected', String(tab === button)));
    if (lastResult && ready && !busy) worker.postMessage({ type: 'stage', id: request, result: lastResult, stage });
  };
});
$('result').addEventListener('click', event => {
  const diagnostic = event.target.closest('[data-line]');
  if (!diagnostic) return;
  const lines = source.value.split('\n');
  const line = Math.max(1, Number(diagnostic.dataset.line));
  const offset = lines.slice(0, line - 1).reduce((sum, text) => sum + text.length + 1, 0) + Math.max(0, Number(diagnostic.dataset.col) - 1);
  source.focus();
  source.setSelectionRange(offset, offset);
  source.scrollTop = Math.max(0, (line - 4) * 22.5);
  position();
});

// ---- boot: shared link > saved draft > default example ----
if (!embed) try {
  const saved = localStorage.getItem('alice.playground.source');
  if (saved !== null) source.value = saved;
} catch { /* The playground works without persistent storage. */ }
const shared = /(?:^#|&)code=([\w.-]+)/.exec(location.hash)?.[1];
if (shared) {
  try { source.value = await unpack(shared); } catch { $('notice').textContent = 'That shared link could not be decoded.'; }
}
edited();
controls();
$('open-playground').onclick = async event => {
  event.preventDefault();
  window.open(new URL('./#code=' + await pack(source.value), location.href), '_blank', 'noopener');
};
if (embed && params.get('run') !== '1') {
  // nothing downloads until the reader presses Run (Ctrl+Enter works too)
  $('result').innerHTML = '<div class="stage-scroll"></div><section class="console" aria-label="Console output"><div class="console-head"><span>Console</span><span class="result-status">Idle</span></div><pre id="console-output"><span class="muted">Press ▶ Run to start .NET and run this example.</span></pre></section>';
  status('Press Run to load .NET');
  controls();
} else start(() => compile(embed && params.get('run') === '1'));
