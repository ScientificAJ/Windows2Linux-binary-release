# Window2Linux Executable Package

This folder contains a standalone Linux executable build and a convenience launcher script.

## Contents

- `window2linux`: standalone CLI executable (ELF)
- `w2l_smart_run.sh`: smart-run wrapper for setup checks and app launch

## Quick Start

From the repository root:

```bash
chmod +x ./binary/window2linux ./binary/w2l_smart_run.sh
./binary/window2linux --help
./binary/w2l_smart_run.sh --help
```

## Run a Windows App

Use the executable directly:

```bash
./binary/window2linux run /path/to/app.exe
./binary/window2linux run /path/to/app.exe --execute
```

Use the smart wrapper:

```bash
./binary/w2l_smart_run.sh /path/to/app.exe
```

Notes:
- `run` defaults to preview mode when using `window2linux` directly.
- `w2l_smart_run.sh` enables `--execute` by default.

## Setup-Only Check

```bash
./binary/w2l_smart_run.sh --setup-only
```

If you want to skip package installation:

```bash
./binary/w2l_smart_run.sh --setup-only --no-install
```

## Common Wrapper Options

```bash
./binary/w2l_smart_run.sh --max-attempts 5 --timeout-seconds 240 /path/to/app.exe
./binary/w2l_smart_run.sh --use-gamescope --gamescope-res 2560x1440 --gamescope-fps 144 /path/to/app.exe
./binary/w2l_smart_run.sh --mode install /path/to/installer.msi
```

## Troubleshooting

- Binary missing execute bit:
  - `chmod +x ./binary/window2linux`
- Wrapper cannot find binary:
  - `./binary/w2l_smart_run.sh --binary /absolute/path/to/window2linux --help`
- Check detected runtime backends:
  - `./binary/window2linux inspect runners --json`
