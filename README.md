# DUDE-Star
Software to RX/TX D-STAR, DMR, Fusion YSF, NXDN, and P25 reflectors and repeaters/gateways over UDP

This software connects to D-STAR, Fusion, NXDN, and P25 reflectors and gateways/repeaters over UDP.  It is similar in functionality to BlueDV (except not as pretty), and is compatible with all of the AMBE3000 based USB devices out there (ThumbDV, DVstick 30, etc). If a compatible DV dongle is detected, TX is enabled.  If no DV dongle is detected, or is in use by another instance of DUDE-Star, then it become a software AMBE decoding application, formerly known as DUDE-Star RX. This software is open source and uses the cross platform C++ library called Qt.  It will build and run on Linux, Windows, and Mac OSX.

This software makes use of software from a number of other open source software projects, including:

MMDVM_CM: https://github.com/nostar/MMDVM_CM

XLXD: https://github.com/LX3JL/xlxd

DSDcc: https://github.com/f4exb/dsdcc

DSD: https://github.com/szechyjs/dsd

MBELIB: https://github.com/szechyjs/mbelib

Not only is software from these projects being used directly, but learning about the various network protocols and encoding/decoding of the various protocols was only possible thanks to the authors of all of these software projects.

# Optional FLite Text-to-speech build
I added Flite TTS TX capability to DUDE-Star so I didn't have to talk to myself all of the time during development and testing.  To build DUDE-Star with Flite TTS support, uncomment the line #define USE_FLITE from the top of dudestar.h. You will need the Flite library and development header files installed on your system.  When built with Flite support, 4 TTS check options and a Mic in option will be available at the bottom of the window.  TTS1-TTS4 are 4 voice choices, and Mic in turns off TTS and uses the microphone for input.  The text to be converted to speech and transmitted goes in the text box under the TTS checkboxes.

# Usage
On first launch, DUDE-Star will attempt to download the DMR ID list and the DPlus host file.  The remaining host files will be downloaded as each one is selected.

Host/Mod: Select the desired host and module (for D-STAR) from the selections.

Callsign:  Enter your amateur radio callsign.  A valid license is required to use this software.  A valid DMR ID is required to connect to DMR servers.

Talkgroup:  For DMR, enter the talkgroup ID number.  A very active TG for testing functionality on Brandmeister is 91 (Brandmeister Worldwide)

MYCALL/URCALL/RPTR1/RPTR2 are always visible, but are only relevent to Dstar modes REF/DCS/XRF.  These fields need to be entered correctly before attempting to TX on any DSTAR reflector.  RPTR2 is automatically entered with a suggested value when connected, but can still be modified for advanced users.

# Compiling on Linux
This software is written in C++ on Linux and requires Qt5 and the usual development packages to build. MBELIB source files are bundled into this project, so a separate mbelib development package is not required. With these requirements met, run the following:
```
qmake
make
```
qmake may have a different name on your distribution i.e. on Fedora it's called qmake-qt5

Notes for building/running Debian/Raspbian:  In addition to the Linux build requirements, there are some additional requirements for running this QT application in order for the audio devices to be correctly detected:
```
sudo apt-get install libqt5multimedia5-plugins
```
And if pulseaudio is not currently installed:
```
sudo apt-get install pulseaudio
```


# One-command Windows build
From a freshly extracted source zip on Windows, open Command Prompt or PowerShell in the DUDE-Star folder and run:
```
.\build-windows.cmd
```

The script bootstraps a private MSYS2/UCRT64 toolchain under `.windows-build`, installs the Qt 5 packages DUDE-Star needs, builds with qmake/mingw32-make, and runs `windeployqt` so the result can be launched from `build\windows\package\dudestar.exe`. No prior Qt, compiler, Git, or administrator setup is required, but the first run does need internet access to download MSYS2 and Qt packages. Later runs reuse the downloaded toolchain. The package install steps disable pacman's low-speed download timeout and retry transient MSYS2 mirror failures automatically, so a slow mirror does not normally require restarting from scratch. The bootstrap also installs MSYS2's ANGLE runtime package because Qt's Windows deployment tool may copy `libEGL.dll` and `libGLESv2.dll` while packaging QtGui.

Optional switches can be passed through the command file, for example:
```
.\build-windows.cmd -Configuration debug
.\build-windows.cmd -SkipDeploy
```

The bootstrap build disables optional FLite text-to-speech support (`CONFIG+=no_flite`) because the stock Windows zip workflow is intended to require no extra FLite libraries.

# Builds
There is currently a 32-bit Windows executable available in the builds directory.  QT and mbelib are statically linked, no dependencies are required.
There is also an Android build called DROID-Star at the Play Store as a beta release.

