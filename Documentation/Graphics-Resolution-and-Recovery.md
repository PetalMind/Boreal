# Graphics resolution and recovery

Boreal uses `GraphicsBackendResolver.rankedCandidates` as the single ordering
for automatic selection, the graphics report, and initialization recovery.
The ranking includes API and executable/prefix architecture constraints,
verified runtime capabilities, component availability and known game rules.

`GraphicsResolutionReport` records requested and selected backends separately.
Its API evidence retains ambiguous imports; ambiguous detection does not select
the highest DirectX version. A legacy wrapper's output API is used when ranking
renderers. OpenGL is presented as Wine OpenGL rather than DirectX translation.

Automatic recovery requires the original preference to be Automatic and no
forced game renderer. Initialization errors must match the resolved backend's
context on the same log line. Ordinary exits and unrelated subsystem errors do
not initiate recovery. Each backend is tried at most once in a recovery series;
when the ranking is exhausted Boreal stops. Recovery does not update the user's
renderer preference. The next attempt activates the backend from a fresh report
using the same runtime and current capabilities.

Compatibility results use executable SHA-256, runtime identity/version,
component version/receipt digest, executable/prefix architecture, API, legacy
wrapper and WineD3D host-renderer preference. Unversioned optional components
without a receipt are excluded from persistent learning; they can still be
skipped within a recovery series. A component update gives a new key. Process
observation is stored as `processObserved`, not proof of successful rendering.
The graphics details include a control to clear learned results while idle.

Prefix graphics activation keeps the existing rollback snapshots for files and
registry overrides. Successful configuration commits that transaction. A new
preparation reservation closes the gap between configuration and starting Wine.
Only the owning operation can mutate or start that prefix during preparation;
a runtime lease protects it afterward. Other launches that need configuration
are rejected while the prefix is in use. Prefix mutations remain blocked even
when a Steam client outlives its game: the client must close before a different
graphics configuration can be applied.

Legacy test profiles A–E remain available in Developer Mode. Normal mode keeps
individual wrapper and legacy API controls.
