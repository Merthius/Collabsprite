# Collabsprite — English guide

[Deutsch](README.md) · [Download v0.4.2 beta](https://github.com/Merthius/Collabsprite/releases/download/v0.4.2/Collabsprite.aseprite-extension)

Collabsprite is an unofficial, open-source Aseprite extension for drawing together on the same pixel-art canvas. The host runs a small local server; everyone uses the **same** extension. Per-user undo/redo applies to synchronized pixel operations without removing newer contributions by someone else.

![Illustrated setup: install, host, join](docs/quick-start.svg)

*The image is a schematic guide, not an Aseprite screenshot.*

> [!WARNING]
> **Windows beta.** Local hosting on one PC has been tested in Aseprite 1.3.18.6. Two-PC Radmin VPN operation, VPN discovery, and starting with Radmin closed still need end-to-end testing. Save your work regularly as an `.aseprite` file.

## Requirements

| | Host | Guest |
| --- | --- | --- |
| Aseprite | Yes | Yes |
| `Collabsprite.aseprite-extension` | Yes | Yes — same version |
| [Node.js](https://nodejs.org/) 20+ | Yes | No |
| [Radmin VPN](https://www.radmin-vpn.com/) | Only across PCs | Only across PCs |

**Local** means multiple Aseprite windows on one computer (`127.0.0.1:8765`). **Global** means computers in the *same Radmin VPN network* (port `8766`), not a public Internet service.

## Install on every computer

1. On the [v0.4.2 release page](https://github.com/Merthius/Collabsprite/releases/tag/v0.4.2), download **`Collabsprite.aseprite-extension`** from **Assets**. Do **not** use GitHub's automatically generated “Source code (zip)” as the installer.
2. In Aseprite, open **Edit → Preferences → Extensions → Add Extension** and select the file. Double-clicking the extension may work as well ([official Aseprite instructions](https://www.aseprite.org/docs/extensions/)).
3. Restart Aseprite. Open **View → Collabsprite…** (in a German UI: **Ansicht → Collabsprite…**).

## Host

1. Open an RGB sprite. Collabsprite creates a **separate session copy**; the original file is not modified.
2. Open **View/Ansicht → Collabsprite… → Create/Erstellen**. Enter your name and choose **Local/Lokal** or **Global/Radmin VPN**.
3. Click **Create session/Sitzung erstellen** and wait for **Connected/Verbunden**.
4. Click **Copy invitation/Einladung kopieren** and privately send the full code to your friends.

For Global mode, everyone must first join the same Radmin VPN network. Collabsprite is intended to open Radmin if it is not running; join your VPN and click Create again. Windows may request approval for a limited firewall rule on the first global start. The user must approve it; the extension cannot bypass this step.

## Join

1. Install the same extension, restart Aseprite, and choose **View/Ansicht → Collabsprite… → Join/Beitreten**. You do not need to open a sprite first.
2. Choose the same connection mode as the host.
3. Paste the **invitation code** and click **Join/Beitreten**. You may also search for active sessions. If Radmin discovery finds nothing, use the code.
4. Wait for **Connected/Verbunden** and draw in the shared session copy.

The entire code is a **session access key**. Never publish it in an issue or screenshot.

## Working together

- Standard Aseprite drawing tools and **completed** selection, paste, fill, and move operations sync. A held stroke or floating selection is not streamed live.
- Any participant can append raster layers and frames using ordinary Aseprite commands. Deleting/reordering layers or frames during a session is not supported yet.
- `Ctrl+Z` / `Ctrl+Y` affect your own synchronized **pixel** actions. Layer/frame creation is not part of that pixel history.
- Save the session copy as `.aseprite` with **Save As**. The host also keeps local session backups, but they do not replace manual saves.
- After a network interruption, there is no automatic reconnect or offline merge. Save the local copy and join deliberately again.

The WebSocket connection has **no built-in end-to-end encryption**; use a trusted VPN across computers. The host checks and orders changes. Local mode listens only on loopback. The invitation code must remain private.

## Limitations and support

RGB/RGBA raster layers are supported, with limits of 8 participants, 1024×1024 pixels, 32 layers, 120 frames, and 4,194,304 cel-pixels. Tilemaps, reference layers, tags, slices, color profiles, linked cels, layer properties, frame durations, selections, zoom, and color choices are not fully synchronized. See [technical notes](docs/technical-notes.md) and [open issues](https://github.com/Merthius/Collabsprite/issues).

Collabsprite is [MIT-licensed](LICENSE) and is not affiliated with Aseprite or Radmin VPN. Contributions are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).
