# Alice Playground

A standalone, static playground written in **Alice**. Edit a program, inspect its typed **HIR**, lowered **MIR**, generated **C#**, and emitted **IL**, then execute that IL on **.NET WebAssembly** in your browser.

The application, compiler orchestration, tree printer, PE disassembler, HTML/CSS views, examples, console capture, release adapter, and native tests are `.al`. JavaScript starts the browser runtime, transports worker messages, binds DOM events, and provides editor ergonomics (highlighting overlay, autocomplete, indentation, share links). There are no authored C# application files.

## Build

On Linux x64, install the .NET 10.0.402 SDK (pinned in `global.json`), its WebAssembly workload, and Python 3.11 or later:

```sh
dotnet workload install wasm-tools
python3 scripts/build.py
python3 scripts/serve.py
```

Open **http://localhost:4173**. The deployable site is **`dist/`**.

The build downloads **Alice v0.10.1** from [GitHub Releases](https://github.com/alicelanguage/alice/releases/tag/v0.10.1) and verifies the pinned SHA-256 in `alice.toml`. It does not reference another folder, a local Alice installation, or a compiler source project. This directory can be its own repository. `alice.toml` is the configuration source of truth; the build generates `.alice/*.alproj` and `.generated/*.g.cs` as temporary .NET build inputs.

`DOTNET=/path/to/dotnet python3 scripts/build.py` selects a particular SDK installation.

## Cloudflare Pages

Git-connected project (Settings → Builds): framework preset **None**, build command **`bash scripts/cloudflare-build.sh`**, build output directory **`dist`**, root directory empty. The script installs the SDK pinned in `global.json` and the `wasm-tools` workload (the Pages image has no .NET), then runs `scripts/build.py`.


Deploy **`dist/` as a static Pages site**. No Functions, Workers backend, database, or .NET server is needed. The build checks that every asset is under Pages’ 25 MiB limit and includes `_headers`, WASM MIME-compatible assets, fingerprinted assemblies, and third-party notices.

For GitHub Actions, put the contents of this directory at the repository root. [`.github/workflows/pages.yml`](.github/workflows/pages.yml) installs the SDK/workload, downloads the pinned release, runs Alice and real-browser tests, and uploads the `cloudflare-pages` artifact.

To deploy from the workflow, set:

- Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- Repository variable: `CLOUDFLARE_PAGES_PROJECT` (an existing Pages project).

Run the workflow manually with **deploy** enabled. Ordinary pushes and pull requests build and test without publishing. Alternatively, upload `dist/` with Wrangler:

```sh
npx wrangler@4.151.1 pages deploy dist --project-name YOUR_PROJECT
```

## Use

- **Compile** builds all four views without executing the program.
- **Run** or **Ctrl/Cmd+Enter** compiles and runs it.
- The console shows printed output and the final expression result separately (for example, `6 * 7` → `42`).
- The source editor, stage view, and console each scroll independently, horizontally and vertically.
- **Stop** terminates the runtime worker; Run starts a fresh one.
- Runs stop automatically after 15 seconds; output is limited to 64 KiB.
- Click a diagnostic to jump to its source position; failing lines are marked in the gutter.
- Autocomplete appears while typing (keywords, Prelude, .NET types/members, names in your program); Tab/Enter accepts, Ctrl+Space opens it.
- **Share** copies a link with the program compressed in the URL fragment; **Download** saves `main.al`.
- Tab/Shift+Tab indent, Enter keeps indentation, `end` dedents, Ctrl+/ toggles comments, Shift+Enter compiles, Esc stops.
- Source is restored from browser-local storage. The application does not submit source to a server.

## Embed in documentation

Any page can turn code blocks into live, editable playgrounds:

```html
<script type="module" src="https://YOUR-PLAYGROUND/embed.js"></script>
<pre data-alice-playground data-run>puts "Hello from the docs"
6 * 7</pre>
```

| Attribute | Effect |
|---|---|
| `data-run` | compile and run on load (otherwise compile only) |
| `data-stages` | show the HIR / MIR / C# / IL tabs above the console |
| `data-readonly` | lock the source |
| `data-height="300"` | iframe height in px (default from the line count) |

Each block becomes an iframe of `/?embed=1&run=1#code=…`: an editor with highlighting and autocomplete, Run/Stop, console, result value and clickable diagnostics (failing examples show their errors), plus **Open in playground ↗**. Embeds never touch the saved draft. The same URL works directly in an `<iframe>`.

## Tests

```sh
python3 scripts/build.py --native-only
npm ci
npx playwright install chromium
npm run test:browser
```

The Alice specifications check real stage content, emitted IL execution, safety diagnostics, compile-only behavior, runtime failures, library inspection, branches, and bounded output. Browser tests run the same pipeline in an actual .NET WASM worker and cover every example, stage tabs, HTML escaping, diagnostics, editor persistence, mobile layout, cancellation, timeout, and restart.

With the preview server running, `/__tests` also exposes the browser-runtime assertions directly. Test reports are saved to `.artifacts/browser-test.json`.

## Layout

| Path | Purpose |
| --- | --- |
| `src/Application/*.al` | Compiler pipeline, results, HIR/MIR dumps, IL disassembly, UI and examples |
| `src/Browser/browser.al` | `.NET` JS exports and reference loading |
| `scripts/prepare_compiler.al` | Browser adaptation of the downloaded release copy |
| `scripts/render.al` | Render the static HTML using Alice |
| `web/*.js` | Browser bootstrap, worker transport, DOM event wiring |
| `scripts/build.py` | Verified release download and .NET build packaging |
| `tests/playground_spec.al` | Alice application specifications |

See [the architecture decision](docs/0001-release-based-browser-playground.md) for browser-specific details. Draco’s playground was a reference for the inspection experience; no Draco source was copied.
