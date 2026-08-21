# VeloxQuant Studio

A native macOS application for the [VeloxQuant-MLX](https://github.com/rajveer43/VeloxQuant-MLX)
ecosystem — quantize, benchmark, and serve MLX models on Apple Silicon through
a polished SwiftUI interface.

This app does not reimplement VeloxQuant-MLX's compression engine. It drives
the existing Python CLI (`veloxquant methods`, `veloxquant serve`,
`veloxquant recommend`) as a subprocess, following the architecture proposed
in [VeloxQuant-MLX#33](https://github.com/rajveer43/VeloxQuant-MLX/issues/33)
and its [implementation plan](https://github.com/rajveer43/VeloxQuant-MLX/blob/master/docs/control-panel-plan.md).

## Requirements

- macOS 14+
- Xcode 16+ (built and verified against Xcode 26.3 / Swift 6.2)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A local Python environment with `veloxquant_mlx` and `mlx_lm` installed
  (`pip install VeloxQuant-MLX`), for the app to drive

## Getting started

```bash
# 1. Generate the Xcode project (VeloxQuantStudio.xcodeproj is gitignored —
#    regenerate it any time project.yml changes)
xcodegen generate

# 2. Configure Supabase auth
cp Secrets.xcconfig.example Secrets.xcconfig
# edit Secrets.xcconfig with your Supabase project URL + anon key

# 3. Open and run
open VeloxQuantStudio.xcodeproj
```

Without a configured `Secrets.xcconfig`, the app still builds and runs — the
auth screen shows a clear "not connected to Supabase" error instead of
crashing, so UI/engine work can proceed independently of backend setup.

## Running the app

**From Xcode (recommended for development):**

```bash
open VeloxQuantStudio.xcodeproj
```

Then press `⌘R`. This gives you live reload, breakpoints, and console logs.

**From the command line:**

```bash
xcodebuild -project VeloxQuantStudio.xcodeproj -scheme "VeloxQuant Studio" \
  -destination "platform=macOS,arch=arm64" build

open ~/Library/Developer/Xcode/DerivedData/VeloxQuantStudio-*/Build/Products/Debug/VeloxQuantStudio.app
```

If `project.yml` has changed since the `.xcodeproj` was last generated, run
`xcodegen generate` again first. For quantization/serving/benchmarking to
work, the app needs a Python interpreter with `veloxquant_mlx` installed —
it will prompt you to auto-detect or select one in Settings → Compute if
none is found.

## Architecture

```
SwiftUI Views
   ↓
ViewModels (@Observable)
   ↓
Service Layer
   ├── AuthenticationService   — Supabase auth, Keychain-backed sessions
   ├── ModelService            — model discovery/import, wraps veloxquant_mlx.ui.models
   ├── QuantizationService     — drives `veloxquant serve`, streams live logs
   ├── BenchmarkService        — drives `veloxquant recommend`
   ├── HardwareService         — Apple Silicon chip/memory via sysctl
   ├── StorageService          — app preferences (storage location, telemetry)
   └── PythonEnvironmentService — locates/validates the Python interpreter
   ↓
VeloxQuant-MLX CLI (subprocess, via Process)
   ↓
MLX / MLX Swift (existing Python engine)
   ↓
Apple Silicon GPU
```

Every service is defined behind a protocol so views/view models never depend
on `Process`, file I/O, or the Supabase SDK directly.

### Why subprocess, not a rewrite

VeloxQuant-MLX's 42 compression methods, Metal kernels, and paper-fidelity
notes live in a mature, independently-tested Python/MLX codebase. Reimplementing
that in Swift for an MVP would both duplicate months of validated work and
drop the paper-deviation/honesty guarantees (`docs/control-panel-plan.md` §4)
that the CLI already enforces. The app instead:

- Decodes `veloxquant methods --json` for the method catalog, serve tiers,
  and per-method config schema — never hardcodes a method list.
- Starts jobs by shelling out to `veloxquant serve`, watching stdout for the
  `VELOXQUANT_READY {...}` handshake to know when a model has actually
  finished loading (not just "process started").
- Surfaces the same accounting-only/honesty banners the CLI prints, so the
  UI can't claim memory savings the backend hasn't proven.

Performance-critical paths can migrate to MLX Swift incrementally later
without changing this app's service boundaries.

## Project layout

```
VeloxQuantStudio/
├── App/            Entry point, AppState (DI root), commands, root nav
├── Models/         Codable/SwiftData types mirroring the Python CLI's JSON
├── Services/        Protocol + implementation per responsibility
├── ViewModels/      @Observable view models, one per major screen
├── Views/           SwiftUI views, grouped by feature
├── Persistence/     SwiftData job history store
├── Support/         ProcessRunner, StreamingProcessController
└── Resources/       Info.plist, entitlements, asset catalog
```

## Security

- No secrets are committed. `Secrets.xcconfig` is gitignored; only
  `Secrets.xcconfig.example` (placeholder values) is tracked.
- Session tokens are stored in the macOS Keychain, never `UserDefaults` or
  SwiftData.
- The app runs without App Sandbox (see `VeloxQuantStudio.entitlements`)
  because it launches `veloxquant serve` as a subprocess — this is a
  deliberate, documented tradeoff, not an oversight.
