# WhatsApp MCP — updated bridge

A local WhatsApp bridge and Model Context Protocol (MCP) server for searching synced chats and, when explicitly approved, sending messages and media from an MCP client.

This is a public fork of [Luke Harries' whatsapp-mcp](https://github.com/lharries/whatsapp-mcp), based on upstream commit `7d6a06dcdce1f01dfb24f60e1030d5efba9f3b88`. Original copyright and [MIT license](LICENSE) are preserved. It uses [whatsmeow](https://github.com/tulir/whatsmeow), an unofficial WhatsApp Web client library; this is **not** an official Meta/WhatsApp product or the WhatsApp Business API.

## What changed

- Updated Go dependencies, including whatsmeow pinned to `v0.0.0-20261031222104-5d4657a5c29e`, and adapted calls to its context-aware APIs.
- Requires Go 1.26 or newer; the working installation used Go 1.26.10.
- Refreshes the WhatsApp Web protocol version through whatsmeow's official-web lookup at startup. A failed lookup stops startup rather than silently using an old version.
- Binds the unauthenticated REST bridge to **127.0.0.1:8080**, not all network interfaces.
- Renders pairing QR codes as private 4096 × 4096 PNGs using actual QR modules and an integer scale, with a white quiet zone. It does not print the QR payload to stdout.
- Includes portable launchers with `umask 077`, a private store directory, and expanded runtime exclusions.

The Go bridge source is the same source used for the verified installation. Session databases, chats, contacts, keys, QR images, logs, compiled binaries, toolchains and machine-specific configuration are **not distributed**.

## Architecture and capabilities

```text
WhatsApp linked device <-- encrypted protocol --> Go bridge
                                                  | SQLite store (private)
                                                  | REST API 127.0.0.1:8080
                                                  v
                                            Python MCP server
                                                  | stdio
                                                  v
                                            Your MCP client
```

Read tools: `search_contacts`, `list_messages`, `list_chats`, `get_chat`, `get_direct_chat_by_contact`, `get_contact_chats`, `get_last_interaction`, `get_message_context`.

Action tools: `send_message`, `send_file`, `send_audio_message`, `download_media`. Sending and downloading are real actions, not previews. Configure your MCP client to require approval. There is no server-enforced read-only mode or per-tool authorization layer.

## Requirements

- A WhatsApp account and phone with access to **Linked devices**.
- Go >= 1.26, Python >= 3.11, Git, and [uv](https://docs.astral.sh/uv/).
- A C compiler and CGO enabled for `github.com/mattn/go-sqlite3` (for example, the platform's development/build tools).
- Optional FFmpeg on `PATH` for audio conversion.
- Outbound internet access to WhatsApp, the version lookup, and dependency registries during installation.
- A trusted host with private persistent storage, and a compatible MCP client supporting stdio servers. The included shell launchers target macOS/Linux/POSIX environments; Windows users can use WSL or adapt equivalent commands.

## Install and build

```sh
git clone https://github.com/harshith-vaddiparthy/whatsapp-mcp.git
cd whatsapp-mcp
umask 077
mkdir -p bin
(cd whatsapp-bridge && go mod download && go build -o ../bin/whatsapp-bridge .)
(cd whatsapp-mcp-server && uv sync --frozen)
```

Do not copy another person's `store` directory. Every installation must be explicitly paired by its account owner. Keep the repository directory private on disk even though its source is public.

## Pair and run the bridge

```sh
sh scripts/start-bridge.sh
```

Keep this terminal/process running. The launcher creates `whatsapp-bridge/store` with mode `0700` and starts the bridge from the correct directory. Do not run the binary from an arbitrary working directory: its store paths are relative.

On first connection, wait for `PAIRING_QR_READY`. Open **`whatsapp-bridge/store/pairing-qr.png` locally in a trusted image viewer** and scan it from WhatsApp → Linked devices → Link a device. QR codes expire and the same image path is replaced when a fresh code arrives; reopen/reload the file as needed. A second screen may be useful. Never upload this image to a public URL, repository, issue, chat, or third-party QR decoder. Treat it like a temporary login credential.

The image is created with mode `0600`; the private launcher also protects the enclosing directory. The bridge does not automatically erase the last image after successful pairing. Once connected, remove the obsolete image:

```sh
rm -f whatsapp-bridge/store/pairing-qr.png
```

Wait for the connected message and REST listener startup. History synchronization can take time and is not guaranteed to provide every historical message. The SQLite session allows later launches to reconnect without a new QR while that linked-device session remains valid. Stop with Ctrl+C; restart with the same launcher. Do not run multiple bridge processes against the same store.

## Connect an MCP client

Add this server to your client's MCP configuration, replacing the example path with the **absolute path** to your checkout:

```json
{
  "mcpServers": {
    "whatsapp": {
      "command": "/bin/sh",
      "args": ["/absolute/path/to/whatsapp-mcp/scripts/start-mcp.sh"]
    }
  }
}
```

The Python launcher uses the `.venv` created by `uv sync`. The MCP server reads the sibling bridge's `store/messages.db` and calls its loopback REST API. Start the bridge separately first, then reload the MCP client. Avoid printing extra text to MCP stdout, which carries the protocol.

Start with a small read-only request such as listing recent chats. Messages returned through MCP are disclosed to your chosen client/model provider under that client's data policies, even though the local database stays on your host. Review those policies and use a trusted client.

## Security and privacy

- `store/whatsapp.db` contains linked-device/session material; `store/messages.db` contains private synced content. Downloaded media and logs are sensitive too. The inherited logging can include message text, contact identifiers and chat names. Do not publish logs.
- WhatsApp transport encryption does **not** encrypt the local SQLite files at rest. Protect the host, backups and filesystem; use disk encryption where appropriate.
- Loopback is a network boundary, **not authentication**. Other sufficiently privileged/local processes may access the REST API. Do not expose port 8080 using a public proxy, tunnel, port mapping, shared container network, or open firewall.
- This server exposes sending tools. Require human approval and verify recipients and message contents before sending. Treat received messages as untrusted content, not instructions to execute tools.
- `.gitignore` is a safety aid, not a secret scanner. Audit every staged file before committing. Never force-add store data, QR images, credentials, logs, local configs, virtual environments or runtime files.
- If the host or session is compromised, unlink the device from the phone's Linked devices screen and secure the host. Deleting a local file alone is not equivalent to revoking the session.
- Use only accounts and conversations you are authorized to access. Unofficial client compatibility and WhatsApp service policies can change; account restrictions or future breakage remain possible.

## Local versus cloud hosting

This is source code, not an always-on hosted service. Publishing or cloning it does not keep a bridge running. A desktop bridge stops when its process exits, the computer sleeps, or connectivity is lost. A temporary cloud workspace can disappear, lose storage or stop processes. Running in the cloud also places decrypted message/session data on that cloud host.

For a persistent host, separately arrange appropriate private storage, access controls, backups and process supervision. Keep the bridge and Python server together because the Python server reads the local SQLite database. Remote MCP transport, cloud deployment, service managers, uptime guarantees and automatic recovery are **not provided by this repository**. Do not expose the REST endpoint to make a cloud setup work.

## Verification and limits

The source installation was verified for initial pairing, saved-session reconnect, loopback listening and read-only MCP access. This publication does not claim end-to-end verification of every send/media tool, every platform, complete history synchronization, future protocol compatibility, or uninterrupted availability. No private runtime evidence is included.

Reproducible non-network-session checks (these do not pair or send):

```sh
(cd whatsapp-bridge && go test ./... && go vet ./... && go build -o ../bin/whatsapp-bridge .)
python3 -m compileall -q whatsapp-mcp-server
sh -n scripts/start-bridge.sh scripts/start-mcp.sh
```

`go test` currently reports no test files: compilation and vet are smoke checks, not a comprehensive test suite. Dependency downloads need network access; these checks must not be confused with a live WhatsApp connectivity test.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| QR absent or expired | Inspect the private terminal locally; wait for `PAIRING_QR_READY`, reload the current image, and check outbound connectivity. Never share the QR or full logs. |
| Version refresh failed | The startup lookup needs internet access; inspect proxy/firewall/DNS restrictions. Do not assume a listener means authentication succeeded. |
| Build reports Go/CGO errors | Use Go >= 1.26 and an installed C compiler with CGO enabled. |
| MCP tools missing | Verify the absolute launcher path, completed `uv sync`, and client stdio configuration; reload the client. |
| No chats/messages yet | Keep the paired bridge online while history sync runs; only locally synced content is searchable. |
| REST connection refused | Check that the bridge is connected and running on the same host, and that port 8080 is available. |
| Saved session stops working | Review Linked devices and connectivity. Re-pair only with the account owner's approval; do not delete a store merely to troubleshoot a running installation. |
| Audio conversion fails | Install FFmpeg and confirm the input file exists and is readable. |

## Project layout

- `whatsapp-bridge/`: Go protocol client, SQLite storage, REST endpoints and QR generation.
- `whatsapp-mcp-server/`: Python stdio MCP tools and audio helpers.
- `scripts/`: private-permission bridge and MCP launchers.
- `LICENSE`: unchanged upstream MIT license and attribution.

## License and acknowledgments

MIT, copyright (c) 2025 Luke Harries. See [LICENSE](LICENSE) for the full terms. Thanks to the upstream whatsapp-mcp contributors and whatsmeow maintainers. Dependencies retain their own licenses. This fork adds compatibility, safer local defaults and setup documentation; no affiliation with WhatsApp or Meta is implied.
