# Boreal Runtime P0

The application never searches Homebrew or the global `PATH` for Wine. A runtime is installed under:

```text
~/Library/Application Support/Boreal/Runtimes/<runtime-id>/
```

Production catalogs must be loaded with `SignedRuntimeCatalogLoader`, which verifies the exact catalog bytes with an embedded Ed25519 public key. Every artifact is then verified independently with streaming SHA-256 before extraction.

Until Boreal publishes its CDN URLs, artifact checksum, signature and public key, release builds intentionally expose no downloadable runtime. This prevents an unverified third-party executable from becoming a silent production dependency.

## Development runtime

Debug builds can use an explicit local catalog:

```text
BOREAL_RUNTIME_CATALOG=/absolute/path/runtime-catalog.json
```

This bypass exists only in `DEBUG`. The catalog is an array of `BorealRuntime` manifests. A local `.tar.xz` artifact can use a `file://` URL; remote artifacts must use HTTPS.

Example manifest shape:

```json
[
  {
    "schemaVersion": 1,
    "id": "wine-11.14-boreal.1",
    "displayName": "Boreal Runtime 0.1",
    "wineVersion": "11.14",
    "architecture": "x86_64",
    "minimumMacOS": "15.0",
    "channel": "stable",
    "requirements": ["rosetta2", "gStreamerFramework"],
    "features": {
      "wow64": true,
      "wineMono": true,
      "wineGecko": true,
      "d3dmetal": false,
      "dxmt": false
    },
    "artifact": {
      "url": "file:///absolute/path/wine-stable-11.14-osx64.tar.xz",
      "sha256": "64-lowercase-hex-characters",
      "compressedSize": 0
    }
  }
]
```

The current upstream Gcenx package is a `.tar.xz` containing a `Wine *.app` bundle. Boreal discovers `Contents/Resources/wine/bin/{wine,wineserver,wineboot}` during installation rather than assuming that layout as a permanent contract. Current Gcenx releases also require `/Library/Frameworks/GStreamer.framework`; the development manifest must declare that requirement.

## Transaction boundary

An app is written to Library only after all of these succeed:

1. runtime validation,
2. atomic runtime installation when needed,
3. isolated environment creation,
4. `wineboot --init`,
5. installer process completion,
6. executable discovery,
7. first Wine process launch.

Failures remove the provisional environment and leave Library unchanged. Logs remain scoped to the environment while it exists.
