# Gamma Screen Pet

Gamma is a tiny floating desktop pet. He lives above your desktop, can be dragged around, and switches between small animated states such as idle walking, waving, jumping, napping, working, reviewing, and oops.

## Features

- Transparent floating desktop window
- Pixel-style animated Gamma sprites
- Right-click action menu
- Click to wave
- Double-click to jump
- Drag left or right to play walking animations
- Idle mode patrols left and right
- Keyboard shortcuts for quick actions

## macOS Version

The macOS version is built with Swift and AppKit.

### Requirements

- macOS 12 or later
- Xcode command line tools with `swiftc`

Install the command line tools if needed:

```bash
xcode-select --install
```

### Build

```bash
./build.sh
```

The app will be created at:

```text
build/Gamma.app
```

### Run

```bash
open build/Gamma.app
```

## Windows Version

The Windows version is built with Python, Tkinter, and Pillow. It uses the same bundled Gamma frame assets.

### Requirements

- Windows 10 or later
- Python 3.10 or later

### Run

Double-click:

```text
run_windows.bat
```

Or run from PowerShell / Command Prompt:

```bat
python -m pip install -r requirements-windows.txt
python Windows\gamma_pet_windows.py
```

### Optional EXE Build

You can package the Windows version with PyInstaller:

```bat
python -m pip install pyinstaller -r requirements-windows.txt
pyinstaller --noconsole --onefile --add-data "Assets;Assets" Windows\gamma_pet_windows.py
```

The generated executable will be under `dist\`.

## Controls

- Right-click Gamma: open the action menu
- Click: wave
- Double-click: jump
- Drag: move Gamma and play left/right walking
- `w`: wave
- `j`: jump
- `r`: work
- `i`: idle patrol
- `Esc`: quit when focused

## Notes

This is an early standalone MVP. The current app uses bundled PNG frame assets and a simple AppKit window; it does not require an API key or internet connection to run.
