# Changelog

## Unreleased

- Version the .NET boot manifest by content so returning devices cannot mix cached compiler code with a newer reference loader and fail with `/refs` permission errors.

- Download compressed .NET assemblies once, verify their original boot hashes, and reuse the bytes for compiler references instead of downloading every DLL again.
- Add a cold-start transfer budget and transport tests for compression, integrity and fallback behavior.
- Fit embedded playgrounds to their iframe height without an outer scrollbar, while preserving scrolling inside the editor and output panels.

## 0.10.1 — 2026-10-16

- Add a standalone Alice-written browser playground using the pinned GitHub release.
- Inspect actual HIR, MIR, C#, and emitted IL; execute compiled programs with .NET WebAssembly.
- Show console output and final expression results separately, with independently scrolling editor, stage and console boxes.
- Add examples, positioned diagnostics, persistent editing, bounded output, cancellation and automatic timeout.
- Publish a static Cloudflare Pages artifact and provide a release-based GitHub Actions build/test/deploy workflow.
