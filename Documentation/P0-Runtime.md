# Boreal Runtime P0

Boreal Runtime is a versioned, self-contained and immutable compatibility package. The application never searches Homebrew, MacPorts, `/usr/local`, `/opt/homebrew`, or the global `PATH` for Wine.

Installed runtimes and mutable Wine prefixes are deliberately separated:

```text
~/Library/Application Support/Boreal/
├── Runtimes/<runtime-id>/
└── Environments/<environment-uuid>/prefix/
```

An environment records its exact runtime ID. Runtime upgrades install side by side and never mutate the runtime used by an existing environment.

## Trust chain

Production catalogs must use `SignedRuntimeCatalogLoader`. It verifies the exact `catalog.json` bytes with the Ed25519 public key embedded in Boreal. The detached `catalog.sig` is the raw 64-byte Ed25519 signature.

For every selected catalog entry, `RuntimeManager` then performs this transaction:

1. validate catalog metadata and reject external runtime dependencies,
2. download over HTTPS,
3. verify the actual compressed size and streaming SHA-256,
4. list the archive and reject absolute or parent-traversing paths,
5. extract to `.installing/<transaction-id>`,
6. reject symlinks escaping the staging root,
7. compare the packaged `runtime.json` with the signed catalog metadata,
8. resolve Wine only through the declared layout,
9. verify executables, licenses, notices, SBOM, platform requirements, and `wine --version`,
10. run `wineboot --init` in a disposable prefix,
11. make the package read-only and atomically rename it into `Runtimes/<runtime-id>`.

Failures remove the download, staging tree, and smoke-test prefix. A runtime is not reported as Ready before every step succeeds.

Apple code signing/notarization and the Boreal catalog signature solve different problems. Executable code in the package must be Developer ID signed and notarized before distribution; the Boreal signature independently authenticates catalog selection and artifact hashes.

## Package layout

The P0 builder normalizes upstream Wine archives into this stable contract:

```text
BorealRuntime/
├── Runtime/Wine.app/
├── Dependencies/
├── Support/
│   ├── wine-mono/
│   ├── wine-gecko/
│   └── winetricks
├── Licenses/
│   └── THIRD_PARTY_NOTICES.txt
├── SBOM.spdx.json
└── runtime.json
```

`Dependencies` contains redistributable frameworks and libraries needed by the packaged Wine build. System GStreamer is intentionally rejected: Rosetta 2 may be a platform requirement, but GStreamer, MoltenVK, SDL, GnuTLS, freetype and similar runtime libraries must be bundled and relocatable.

Mono and Gecko are pinned components. When `features.wineMono` or `features.wineGecko` is true, the corresponding component version and support directory are mandatory. P0 deliberately leaves D3DMetal and DXMT disabled.

When present, `Support/winetricks` is used from the runtime package. Older and locally imported runtimes are supported too: Boreal downloads the official Winetricks script once into `Application Support/Boreal/Tools/Winetricks`, caches it, and invokes it with the selected environment's `WINEPREFIX`. The global PATH and any user-managed Wine prefix are never used. The environment records a small receipt under `.boreal-dependencies` and the UI also verifies the resulting DLLs in `drive_c/windows`.

The package manifest does not contain the artifact URL, size, or SHA-256 because embedding the artifact hash inside the artifact would be self-referential. Those fields live only in the signed catalog entry. All other fields must match exactly.

See [`Tools/RuntimeBuilder/runtime.example.json`](../Tools/RuntimeBuilder/runtime.example.json) for schema version 1.

## Building a development artifact

The builder accepts an upstream `.tar.xz` as input, normalizes its `Wine*.app` to `Runtime/Wine.app`, adds already-collected dependencies/support/licenses/SBOM, checks the canonical executables, and rejects absolute non-system Mach-O dependency paths. Bundled references must use relocatable `@rpath`, `@loader_path`, or `@executable_path` install names.

```bash
Tools/RuntimeBuilder/build-runtime.sh \
  upstream-wine.tar.xz \
  runtime.json \
  ./Dependencies \
  ./Support \
  ./Licenses \
  ./SBOM.spdx.json \
  ./dist/BorealRuntime.tar.xz
```

The printed SHA-256 and byte size belong in the external catalog entry. Its metadata mirrors `runtime.json`, adds `requirements: ["rosetta2"]`, and adds the artifact object with an HTTPS URL, SHA-256 and compressed byte size.

Debug builds can load an explicit local catalog with `BOREAL_RUNTIME_CATALOG=/absolute/path/catalog.json`; local artifacts may use `file://`. Release builds intentionally expose no downloadable runtime until real CDN URLs and an embedded production Ed25519 key are configured.

## Production pipeline

The intended release sequence is: pinned Wine source and Boreal patches → reproducible build → dependency bundling → relocation audit → license collection and SPDX SBOM → Developer ID signing → notarization → normalized package → SHA-256 and size → signed catalog → CDN publication.

The builder is the P0 normalization boundary. A later first-party Wine build pipeline can replace its upstream input without changing the package contract or the application-side installer.
