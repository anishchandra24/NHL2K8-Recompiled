# NHL 2K8 Recompiled

![NHL 2K8 Recompiled](docs/banner.png)

A native Windows port of 2K Sports NHL 2K8 for the Xbox 360, made with static recompilation via the ReXGlue SDK.

> Unofficial fan project. Not affiliated with or endorsed by Take-Two Interactive, 2K Sports, Visual Concepts, Kush Games, the NHL or the NHLPA. All trademarks belong to their owners. This repository contains no game files and no game code. The banner image uses artwork and logos owned by their respective owners, for identification only. You need your own legally obtained copy of the game. Requests for or links to game files will be removed.

## What this is

This repository holds the pieces that make the ReXGlue SDK work with NHL 2K8: the fix list that lets the recompiler understand the game, a small launcher program, and a patch that adds the in-game music (menu music has been reported silent in the Xenia emulator). The game itself is translated on your own computer from your own copy.

## Status

Works:
- Boots, menus, quick games, franchise mode, tournaments, saving and loading
- Keyboard and controller input
- Achievements
- Soundtrack through the game's built-in music player (2K Beats)
- The game's own icon on the window, taskbar and shortcut

Known issues:
- Some 2D graphics (logos, banners) have paler reds than on a real Xbox 360. The same problem is reported in the Xenia emulator.
- Many parts of the game look brighter than on a real Xbox 360, another issue seen in Xenia. The 3D player models look correct.
- Small colored speckles around the edges of the intro logo videos.
- Stutter in busy scenes with a full crowd (pond hockey and mini rink run smoothly).
- The F4 settings screen's "Save to config" button writes a config file the game can't read (a ReXGlue SDK bug). Edit settings by hand with forward slashes in paths.
- Online features do not work.
- Custom soundtracks have not been tested.

## What you need

- Windows 10 or 11, 64-bit
- Your own copy of NHL 2K8 for Xbox 360 (Title ID 54540809, version 0.0.0.3), extracted so that you have `default.xex` and the game's files in one folder. The supported `default.xex` is 9,383,936 bytes with the SHA-256 hash `BA4E63334FAF296019657C6E86BBD444CB05646E29FA6C7B72F4BF9709CE4225`.
- Visual Studio 2022 with the C++ Clang tools (tested with Clang 19.1.5), plus CMake and Ninja
- The ReXGlue SDK, version 0.10.0 (commit c94f5eb)

## Setup

Setup instructions are coming soon. A setup script that builds everything from your own game folder is being written and tested.

## Controls (keyboard)

Keyboard mode must be on (`mnk_mode`). Defaults:
- Start: Enter or X
- A: Space or ;  B: Backspace or '  X: L  Y: P
- Left stick (skate): W A S D   Right stick (ProStick): arrow keys
- Triggers: Q / E (or I / O)   Shoulders: 1 and 3
- Back: Tab or Z
- F3 shows performance info, F4 shows settings

An XInput game controller also works.

## How this was made

This project was developed in a chat conversation with Claude, an AI assistant by Anthropic. Claude wrote the diagnostic commands, configuration fixes, code and patches. Claude had no access to the developer's computer: everything it wrote was copied in by hand, run and tested by the project owner (anishchandra24), who also reported what happened, supplied knowledge of the original game, and made all decisions. Claude Code was not used. It has been tested on one machine (Windows 10 Home, AMD Ryzen 7 7735HS, NVIDIA RTX 4060 Laptop GPU and AMD Radeon integrated graphics, 32 GB RAM) and has not been reviewed by anyone else.

## Credits

- anishchandra24: project, fixes and testing
- The ReXGlue SDK by Tom Clay and contributors
- The Xenia project (Ben Vanik and contributors), whose work the SDK's graphics code builds on
- Claude (Anthropic): AI assistant used to write code, patches and diagnostics (see "How this was made")

## License

The files in this repository are released under the GNU General Public License v3.0 (see LICENSE). The license covers only what this project is entitled to license. The banner image shows artwork and logos owned by their respective owners and is not covered by this license. It grants no rights to the game's files, or to anything generated from them on your own computer. The music patch modifies code from the ReXGlue SDK and Xenia, which keep their own BSD licenses (see THIRD_PARTY_NOTICES.md).

