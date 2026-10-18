#!/usr/bin/env python3
"""Standalone release-based Alice playground build. No sibling directory or source checkout required."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tomllib
from urllib.request import urlopen
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent.parent
CONFIG = tomllib.loads((HERE / "alice.toml").read_text())
ARTIFACTS = HERE / ".artifacts"
TOOLS = HERE / ".toolchain"
DOTNET = os.environ.get("DOTNET", "dotnet")
ENV = dict(os.environ,
    NUGET_HTTP_CACHE_PATH=os.environ.get("NUGET_HTTP_CACHE_PATH", str(ARTIFACTS / "nuget-http")),
    NUGET_PACKAGES=os.environ.get("NUGET_PACKAGES", str(ARTIFACTS / "nuget-packages")),
    DOTNET_CLI_TELEMETRY_OPTOUT="1")
LIBRARIES = ["Alice.Compiler", "Alice.Runtime", "Microsoft.CodeAnalysis", "Microsoft.CodeAnalysis.CSharp"]

def run(*args):
    subprocess.run([str(x) for x in args], cwd=HERE, env=ENV, check=True)

def fetch(url, path, expected):
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        path.parent.mkdir(parents=True, exist_ok=True)
        print("Downloading " + url, flush=True)
        with urlopen(url) as response, path.open("wb") as output:
            shutil.copyfileobj(response, output)
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise RuntimeError(f"Checksum mismatch for {path.name}: {actual}")

def toolchain():
    if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
        raise RuntimeError("The pinned build toolchain targets Linux x64 (also used by GitHub Actions and Pages).")
    config = CONFIG["toolchain"]
    version = config["version"]
    archive = TOOLS / "downloads/alice.tar.gz"
    fetch(f"https://github.com/{config['repository']}/releases/download/v{version}/alice-{version}-linux-x64.tar.gz", archive, config["linux_x64_sha256"])
    release = TOOLS / "release"
    identity = f"{config['repository']}@{version}:{config['linux_x64_sha256']}"
    marker = release / ".release-identity"
    if not marker.exists() or marker.read_text() != identity:
        if release.exists():
            shutil.rmtree(release)
        release.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive) as package:
            package.extractall(release, filter="data")
        marker.write_text(identity)
    cecil_package = TOOLS / "downloads/cecil.zip"
    fetch(f"https://api.nuget.org/v3-flatcontainer/mono.cecil/{config['cecil_version']}/mono.cecil.{config['cecil_version']}.nupkg", cecil_package, config["cecil_sha256"])
    cecil = TOOLS / "cecil/lib/netstandard2.0/Mono.Cecil.dll"
    if not cecil.exists():
        with ZipFile(cecil_package) as package:
            package.extract("lib/netstandard2.0/Mono.Cecil.dll", TOOLS / "cecil")
    prepared = TOOLS / "browser"
    prepared.mkdir(exist_ok=True)
    for pattern in ("*.dll", "*.json"):
        for file in release.glob(pattern):
            shutil.copy2(file, prepared / file.name)
    # This adapter is Alice too. Only the downloaded copy is changed, never a release or source tree.
    run(DOTNET, release / "alice.dll", "run", HERE / "scripts/prepare_compiler.al", "-r", cecil, "--",
        release / "Alice.Compiler.dll", prepared / "Alice.Compiler.dll")
    return prepared

def project(name, groups, browser=False, test=False):
    target = HERE / ".alice" / (name + ".alproj")
    target.parent.mkdir(exist_ok=True)
    sdk = "Microsoft.NET.Sdk.WebAssembly" if browser else "Microsoft.NET.Sdk"
    extra = """
    <RuntimeIdentifier>browser-wasm</RuntimeIdentifier>
    <OutputType>Exe</OutputType>
    <WasmMainJSPath>$(PlaygroundRoot)/web/runtime.js</WasmMainJSPath>
    <WasmEnableHotReload>false</WasmEnableHotReload>
    <WasmEnableWebcil>false</WasmEnableWebcil>
    <PublishTrimmed>false</PublishTrimmed>
    <WasmBuildNative>false</WasmBuildNative>
""" if browser else ("<OutputType>Exe</OutputType>" if test else "")
    includes = ";".join("$(PlaygroundRoot)/.generated/" + group + "/*.g.cs" for group in groups)
    refs = "\n".join(f'    <Reference Include="{name}"><HintPath>$(PlaygroundRoot)/.toolchain/browser/{name}.dll</HintPath></Reference>' for name in LIBRARIES)
    target.write_text(f'''<!-- Generated from alice.toml by scripts/build.py. -->
<Project Sdk="{sdk}">
  <PropertyGroup>
    <TargetFramework>{CONFIG['package']['target']}</TargetFramework>
    <LanguageTargets>$(MSBuildToolsPath)/Microsoft.CSharp.targets</LanguageTargets>
    <LangVersion>preview</LangVersion>
    <AssemblyName>{name}</AssemblyName>
    <Version>{CONFIG["package"]["version"]}</Version>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><AllowUnsafeBlocks>true</AllowUnsafeBlocks>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>{extra}
  </PropertyGroup>
  <ItemGroup>
{refs}
    <Compile Include="{includes}" />
  </ItemGroup>
</Project>
''')
    return target

def build(project_file, publish=False):
    run(DOTNET, "publish" if publish else "build", project_file, "-c", "Release", "--artifacts-path", ARTIFACTS,
        "-p:PlaygroundRoot=" + str(HERE), "--nologo")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--native-only", action="store_true")
    args = parser.parse_args()
    prepared = toolchain()
    cli = prepared / "alice.dll"
    sources = sorted(HERE.glob(CONFIG["playground"]["core"]))
    run(DOTNET, cli, "gen", *sources, "-o", HERE / ".generated/core")
    build(project("Alice.Playground.Application", ["core"]))
    core_dll = ARTIFACTS / "bin/Alice.Playground.Application/release/Alice.Playground.Application.dll"
    run(DOTNET, cli, "gen", *sources, HERE / "tests/playground_spec.al", "-o", HERE / ".generated/tests")
    build(project("Alice.Playground.Specs", ["tests"], test=True))
    run(DOTNET, ARTIFACTS / "bin/Alice.Playground.Specs/release/Alice.Playground.Specs.dll")
    if args.native_only:
        return
    browser_sources = sorted(HERE.glob(CONFIG["playground"]["browser"]))
    run(DOTNET, cli, "gen", *sources, *browser_sources, "-o", HERE / ".generated/browser")
    build(project("Alice.Playground.Browser", ["browser"], True), publish=True)
    bundles = list((ARTIFACTS / "publish/Alice.Playground.Browser").glob("**/wwwroot"))
    if not bundles:
        bundles = list((ARTIFACTS / "bin/Alice.Playground.Browser").glob("**/AppBundle"))
    if not bundles:
        raise RuntimeError("WebAssembly publish produced no static browser assets")
    dist = HERE / CONFIG["playground"]["output"]
    if dist.exists():
        shutil.rmtree(dist)
    shutil.copytree(bundles[-1], dist)
    for file in (HERE / "web").iterdir():
        if file.is_file():
            shutil.copy2(file, dist / file.name)
        elif file.is_dir():
            # fonts/ and brand/ match the Alice site (DM Sans, Fraunces, rabbit mark)
            shutil.copytree(file, dist / file.name, dirs_exist_ok=True)
    run(DOTNET, cli, "run", *sources, HERE / "scripts/render.al", "--", dist / "index.html")
    framework = dist / "_framework"
    boot_js = (framework / "dotnet.js").read_text()
    boot = json.loads(boot_js.split("/*json-start*/", 1)[1].split("/*json-end*/", 1)[0])
    resources = [asset for group in boot["resources"].values() if isinstance(group, list) for asset in group]
    referenced = {asset["name"] for asset in resources}
    # Incremental SDK publishes retain obsolete fingerprints. Ship only this boot manifest's assets.
    for asset in framework.iterdir():
        base = asset.name.removesuffix(".br").removesuffix(".gz")
        if base != "dotnet.js" and base not in referenced:
            asset.unlink()
    # dotnet.js embeds the assembly manifest and changes with each app build.
    # A new URL also bypasses immutable copies already stored on returning devices.
    entry_bytes = (framework / "dotnet.js").read_bytes()
    entry_name = "dotnet." + hashlib.sha256(entry_bytes).hexdigest()[:16] + ".js"
    (framework / entry_name).write_bytes(entry_bytes)
    runtime = dist / "runtime.js"
    runtime.write_text(runtime.read_text().replace("'./_framework/dotnet.js'", f"'./_framework/{entry_name}'"))
    dlls = sorted(framework / asset["name"] for asset in resources if asset["name"].endswith(".dll"))
    if not dlls:
        raise RuntimeError("Expected untrimmed .dll assets (WasmEnableWebcil=false)")
    for notice in ("LICENSE", "NOTICE"):
        shutil.copy2(TOOLS / "release" / notice, dist / notice)
    oversized = [str(p.relative_to(dist)) for p in dist.rglob("*") if p.is_file() and p.stat().st_size > 25 * 1024 * 1024]
    if oversized:
        raise RuntimeError("Cloudflare Pages 25 MiB asset limit exceeded: " + ", ".join(oversized))
    print(f"Static Pages artifact: {dist} ({len(dlls)} managed assemblies)")

if __name__ == "__main__":
    main()
