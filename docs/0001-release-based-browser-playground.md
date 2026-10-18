# ADR 0001: Standalone Alice application on .NET WebAssembly

Status: Accepted

## Decision

Write the application in Alice and use the published Alice v0.10.1 release as its build toolchain and hosted compiler. All dependency paths stay within the playground directory. Pin release/package hashes in `alice.toml`; generate .NET build wrappers in `.alice`, not hand-maintained C# projects.

Keep Alice’s single backend: parser → binder/typed HIR → lowerer/MIR → C# → Roslyn PE/IL. The browser executes that PE using the .NET Mono WebAssembly interpreter. HIR is the actual annotated syntax tree. MIR is captured at the emitter’s printer boundary, including specialized bodies. IL is decoded from the actual emitted PE using `System.Reflection.Metadata`, with operands, metadata names, branch targets, switch targets, and exception regions.

Render the complete page and results in Alice. A small JavaScript shell supplies the browser’s DOM events and worker lifecycle. The .NET runtime and Roslyn live in one dedicated worker, so termination remains available when a user program never yields. A fresh worker gives cancellation recovery and bounds retained generated assemblies. No compilation service runs on Cloudflare.

## Release adaptation

The published compiler assumes desktop facilities in a few places. `scripts/prepare_compiler.al` uses checksum-pinned Mono.Cecil during the build to adapt a **local copy** of its DLL:

1. Guard eager reflection-proxy initialization with `RuntimeFeature.IsDynamicCodeSupported`. On browser runtimes, proxy lookup returns the existing CLR type or no proxy instead of invoking unsupported `Reflection.Emit`.
2. Disable Roslyn’s concurrent build for a single-threaded WASM host.
3. Use a noncollectible assembly load context (collectible contexts are unsupported in browser Mono).
4. Add an optional MIR observer at the existing C# printer boundary.
5. Write portable IL rather than retaining the release’s Linux ReadyToRun machine code.

Desktop proxy behavior, language checks, optimizations, race safety, and null-safety diagnostics are retained. The adapter fails if expected release methods are absent. The release itself and the Alice source repository are untouched. This can be removed when a future release provides these browser hooks directly.

The browser bootstrap downloads the SDK's gzip assets through .NET's resource-loader hook, decompresses them and verifies the original boot-manifest SHA-256 before loading them. It also places the same assembly bytes into `/refs` in .NET’s virtual filesystem, using the manifest's original assembly names. The Alice browser host sets the trusted-platform paths from those files before invoking Roslyn. There is no second assembly download pass or separate reference manifest. These same untrimmed assemblies supply Roslyn metadata and the compiler’s CLR reflection view. Trimming and AOT remain disabled because the playground compiles arbitrary new code and accesses types by reflection. Hosts without gzip assets fall back to the original verified files.

The SDK is pinned to 10.0.402. Earlier Mono releases have a [known Roslyn-triggered `Volatile.ReadBarrier` recursion bug](https://github.com/dotnet/runtime/pull/130303), fixed in .NET 10.0.11. A desktop-only test does not catch this failure.

## Constraints

Browser-hosted .NET has browser capabilities. Native libraries, desktop UI, subprocesses, blocking console input, and OS filesystem/network access are unavailable. Input reads EOF; file IO uses the runtime’s virtual filesystem. Thread-dependent programs and advanced generic CLR reflection requiring emitted proxy types may be unavailable. The playground preserves Alice’s purity/race checks; it does not force unsafe parallelization to work around browser constraints.

The untrimmed runtime and Roslyn require a larger first download. A browser regression test limits compressed assembly/WASM transfers to 24 MiB and rejects duplicate assembly downloads. Individual assets must stay below Cloudflare Pages’ 25 MiB limit. `_framework` assets are fingerprinted and requested with immutable cache reuse. The build also fingerprints `dotnet.js`, which embeds the assembly manifest, and rewrites the bootstrap import to prevent mixed versions on returning devices. The unversioned entry revalidates. No source or compiled user assembly is sent to a backend by the playground.

## Verification

Run the Alice-native specifications and the real-browser workflow. Native tests alone are insufficient to establish WebAssembly execution. The browser suite checks compilation, stage contents, output, diagnostics, cancellation, restart, timeout, and responsive UI from the published static artifact.

References: [Alice release](https://github.com/alicelanguage/alice/releases/tag/v0.10.1), [.NET browser interop](https://learn.microsoft.com/aspnet/core/client-side/dotnet-interop/wasm-browser-app?view=aspnetcore-10.0), [.NET browser hosting](https://github.com/dotnet/runtime/blob/main/src/mono/wasm/features.md), [Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits/).
