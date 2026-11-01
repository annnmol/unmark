# AI access (MCP)

Unmark includes a local MCP server. An AI client can open images, inspect previews, clean selected areas and export the results using the same engine as the editor.

## Connect

1. Open **Unmark → Settings → AI access** and enable **AI access (MCP)**.
2. Copy the address and token into your AI client's MCP connection settings.
3. Select **Streamable HTTP** and use the token as a **Bearer token**. Clients with a headers field should send `Authorization: Bearer YOUR_TOKEN`.
4. Keep Unmark and an image window open. FFmpeg and FFprobe must be installed for cleanup.

The default endpoint is `http://127.0.0.1:7421/mcp`. You can change the port in Settings. If the port is in use, select another port and apply it. No hosted service, Node.js or separate server installation is required.

Your client must support local Streamable HTTP MCP and custom Bearer tokens. A cloud-only connector cannot reach this Mac's loopback address. Connection configuration varies between AI clients; this version does not provide a stdio bridge or an OAuth sign-in flow.

## Tools

| Tool | Action |
| --- | --- |
| `import_images` | Open up to 20 local images per call and return image IDs. |
| `list_images` | Read image IDs, dimensions, edit counts and progress. |
| `preview_image` | Return the current or original image as a PNG preview, up to 1024 pixels on its longest side. |
| `clean_image` | Apply the small/large sparkle preset or a custom rectangle. Successive edits accumulate. |
| `export_image` | Save the result to a new file, using PNG or the original format. |
| `reset_image` | Discard an image's edits and restore its original. |
| `check_tools` | Check FFmpeg, FFprobe and delogo support. |
| `cancel_operation` | Cancel the active window's current operation. |

Custom rectangles use **normalized coordinates from the top-left**, relative to the oriented image. For example:

```json
{
  "image_id": "ID_FROM_IMPORT_OR_LIST",
  "mode": "custom",
  "region": { "x": 0.7, "y": 0.8, "width": 0.15, "height": 0.1 }
}
```

Leave a little space from image edges. Cleanup interpolates surrounding pixels; detailed backgrounds can leave a visible patch. The agent must inspect the image and choose a region; Unmark does not automatically detect arbitrary watermarks.

Actions appear in the most recently active image window. Cleanup and export show progress and use the editor's Cancel button. While the window is busy, new edit commands return a busy error. Agents can also cancel through MCP. Closing that image window cancels its work and removes temporary results.

## Access and files

- The listener binds only to `127.0.0.1`. Every request requires the token. Foreign browser origins are rejected.
- AI imports and exports are limited to absolute paths inside your home folder, including after resolving symbolic links. Images dropped into the editor from elsewhere can still be edited there.
- Imports retain the editor's per-image size limit of 10 MB; AI import calls allow at most 100 images in a window.
- Originals are preserved. Exports never overwrite an existing file, and the destination extension must match the selected output format. If the original format cannot be written, use a `.png` destination.
- The port, enabled preference and token survive app restarts. The token is stored in `~/Library/Application Support/Unmark/Automation/token`, readable only by your macOS user. Treat it as a password.
- **New token** revokes existing sessions and cancels their running work. Update the token in your AI client afterward. Switching access off disconnects clients and cancels their running work, while keeping the token for the next connection.
- Connected counts track MCP sessions. Clients can end them explicitly; otherwise they expire after 30 minutes of inactivity. Session IDs are new after each app restart.

All image processing runs on your Mac. An AI client may send previews or tool results to its model provider according to that client's settings.

## Protocol

MCP uses JSON-RPC 2.0 over Streamable HTTP at `/mcp`, with JSON responses and `MCP-Session-Id` session tracking. Supported negotiated versions are `2025-11-25`, `2025-06-18`, `2025-03-26` and `2024-11-05`. Older versions here use the current HTTP transport, not the legacy SSE transport.

The server supports initialization, ping, tool discovery/calls, cancellation notifications and session deletion. GET returns 405 because a persistent server notification stream is not offered. Request bodies are limited to 64 KiB. FFmpeg execution retains the editor's time limits. Clients should allow at least 120 seconds for a cleanup call.
