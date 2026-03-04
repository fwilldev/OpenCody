# OpenCode Local Server — iOS App API Reference & Gap Analysis

> **Purpose**: Complete wire-format reference for the OpenCode local server API, focused on identifying **gaps and corrections** for an existing SwiftUI iOS app.
>
> **Target Server**: `packages/opencode/src/server/` — Hono on Bun, default port `4096`
>
> **NOT covered**: The `packages/console/app/` SolidStart web console (opencode.ai SaaS) — that's a separate cloud product using server functions, not relevant for the iOS app.

---

## Table of Contents

1. [Connection & Auth](#1-connection--auth)
2. [Workspace Context (CRITICAL)](#2-workspace-context-critical)
3. [SSE Event Streams](#3-sse-event-streams)
4. [Complete API Endpoints](#4-complete-api-endpoints)
5. [Wire-Format Schemas](#5-wire-format-schemas)
6. [Streaming & Prompt Patterns](#6-streaming--prompt-patterns)
7. [WebSocket (PTY Only)](#7-websocket-pty-only)
8. [OpenAPI Spec Gap Analysis](#8-openapi-spec-gap-analysis)
9. [iOS App Checklist — Gaps & Corrections](#9-ios-app-checklist--gaps--corrections)

---

## 1. Connection & Auth

### Server Discovery

The local server runs on `http://localhost:4096` by default. The port can be customized.

### Authentication

Authentication is **optional** — only active when env vars are set:

| Env Var                    | Purpose                                |
| -------------------------- | -------------------------------------- |
| `OPENCODE_SERVER_PASSWORD` | Basic auth password                    |
| `OPENCODE_SERVER_USERNAME` | Basic auth username (default: `admin`) |

When set, **every request** must include:

```
Authorization: Basic base64(username:password)
```

**iOS Gap Check**: Does your app support optional basic auth? It should gracefully handle both auth-required and no-auth servers.

### CORS

The server allows these origins:

- `http://localhost:*` / `http://127.0.0.1:*`
- `tauri://*`
- `*.opencode.ai`
- Custom origins via `OPENCODE_SERVER_ORIGIN` env var

**iOS Note**: Native HTTP clients don't need CORS. This is informational only.

---

## 2. Workspace Context (CRITICAL)

**Every request** (except `/log`, `/global/*`, and `/doc`) requires workspace context via **query params OR headers**:

| Query Param | Header                 | Required | Description            |
| ----------- | ---------------------- | -------- | ---------------------- |
| `workspace` | `x-opencode-workspace` | YES      | Workspace identifier   |
| `directory` | `x-opencode-directory` | YES      | Project directory path |

**Example**:

```
GET /session/?workspace=default&directory=/Users/me/myproject
```

or

```
GET /session/
x-opencode-workspace: default
x-opencode-directory: /Users/me/myproject
```

**iOS Gap Check**: Are you sending workspace + directory on EVERY non-global request? Missing these will cause 400 errors. The middleware parses these before any route handler runs.

---

## 3. SSE Event Streams

### Two SSE Endpoints

| Endpoint            | Scope                                     | Use Case                               |
| ------------------- | ----------------------------------------- | -------------------------------------- |
| `GET /event`        | Per-instance (requires workspace context) | Main event stream for a single project |
| `GET /global/event` | Global (no workspace context needed)      | Cross-project events, wraps payload    |

### Per-Instance SSE (`GET /event`)

Each SSE message is:

```
data: {"type":"event.type","properties":{...}}
```

**On connect**: Immediately sends `server.connected` event.
**Heartbeat**: Every 10 seconds sends `server.heartbeat`.

### Global SSE (`GET /global/event`)

Each SSE message wraps the payload with directory context:

```
data: {"directory":"/path/to/project","payload":{"type":"event.type","properties":{...}}}
```

Also sends `server.connected` on connect and `server.heartbeat` every 10s.

### Reconnection

The TUI client uses **250ms retry delay** on SSE disconnect. iOS should implement similar reconnection logic with the `server.connected` event as confirmation.

### Complete Event Catalog

#### Server Events

| Event Type                 | Properties              |
| -------------------------- | ----------------------- |
| `server.connected`         | `{}`                    |
| `server.heartbeat`         | `{}`                    |
| `server.instance.disposed` | `{ directory: string }` |
| `global.disposed`          | `{}`                    |

#### Session Events

| Event Type          | Properties                                          |
| ------------------- | --------------------------------------------------- |
| `session.created`   | `{ info: Session.Info }`                            |
| `session.updated`   | `{ info: Session.Info }`                            |
| `session.deleted`   | `{ info: Session.Info }`                            |
| `session.diff`      | `{ sessionID: string, diff: FileDiff[] }`           |
| `session.error`     | `{ sessionID?: string, error: any }`                |
| `session.status`    | `{ sessionID: string, status: SessionStatus.Info }` |
| `session.idle`      | `{ sessionID: string }` — **deprecated**            |
| `session.compacted` | `{ sessionID: string }`                             |

#### Message Events

| Event Type             | Properties                                               |
| ---------------------- | -------------------------------------------------------- |
| `message.updated`      | `{ info: MessageV2.Info }`                               |
| `message.removed`      | `{ sessionID: string, messageID: string }`               |
| `message.part.updated` | `{ part: MessageV2.Part }`                               |
| `message.part.delta`   | `{ sessionID, messageID, partID, field, delta: string }` |
| `message.part.removed` | `{ sessionID, messageID, partID: string }`               |

#### Todo Events

| Event Type     | Properties                                  |
| -------------- | ------------------------------------------- |
| `todo.updated` | `{ sessionID: string, todos: Todo.Info[] }` |

#### Permission Events

| Event Type           | Properties                                                        |
| -------------------- | ----------------------------------------------------------------- |
| `permission.asked`   | Full `PermissionNext.Request` object                              |
| `permission.replied` | `{ sessionID, requestID, reply: "once" \| "always" \| "reject" }` |

#### Question Events

| Event Type          | Properties                                      |
| ------------------- | ----------------------------------------------- |
| `question.asked`    | Full `Question.Request` object                  |
| `question.replied`  | `{ sessionID, requestID, answers: string[][] }` |
| `question.rejected` | `{ sessionID, requestID: string }`              |

#### PTY Events

| Event Type    | Properties                         |
| ------------- | ---------------------------------- |
| `pty.created` | `{ info: Pty.Info }`               |
| `pty.updated` | `{ info: Pty.Info }`               |
| `pty.exited`  | `{ id: string, exitCode: number }` |
| `pty.deleted` | `{ id: string }`                   |

#### File Events

| Event Type             | Properties                                               |
| ---------------------- | -------------------------------------------------------- |
| `file.edited`          | `{ file: string }`                                       |
| `file.watcher.updated` | `{ file: string, event: "add" \| "change" \| "unlink" }` |

#### Project/VCS Events

| Event Type           | Properties                 |
| -------------------- | -------------------------- |
| `project.updated`    | Full `Project.Info` object |
| `vcs.branch.updated` | `{ branch?: string }`      |

#### MCP Events

| Event Type                | Properties                         |
| ------------------------- | ---------------------------------- |
| `mcp.tools.changed`       | `{ server: string }`               |
| `mcp.browser.open.failed` | `{ mcpName: string, url: string }` |

#### LSP Events

| Event Type               | Properties                           |
| ------------------------ | ------------------------------------ |
| `lsp.updated`            | `{}`                                 |
| `lsp.client.diagnostics` | `{ serverID: string, path: string }` |

#### Command Events

| Event Type         | Properties                                          |
| ------------------ | --------------------------------------------------- |
| `command.executed` | `{ name, sessionID, arguments, messageID: string }` |

#### Installation Events

| Event Type                      | Properties            |
| ------------------------------- | --------------------- |
| `installation.updated`          | `{ version: string }` |
| `installation.update-available` | `{ version: string }` |

#### Workspace/Worktree Events

| Event Type         | Properties                         |
| ------------------ | ---------------------------------- |
| `workspace.ready`  | `{ name: string }`                 |
| `workspace.failed` | `{ message: string }`              |
| `worktree.ready`   | `{ name: string, branch: string }` |
| `worktree.failed`  | `{ message: string }`              |

**iOS Gap Check**: Are you handling ALL of these event types? Key ones for basic functionality:

- `session.created/updated/deleted` — session list updates
- `session.status` — busy/idle/retry state
- `message.updated` — message metadata changes
- `message.part.updated` — real-time part updates (text streaming, tool progress)
- `message.part.delta` — incremental text deltas (most efficient for streaming text)
- `permission.asked` — MUST handle, or agent blocks forever
- `question.asked` — MUST handle, or agent blocks forever
- `todo.updated` — task list updates

---

## 4. Complete API Endpoints

### Global Routes (no workspace context needed)

| Method | Path              | Operation              | Request                       | Response                             |
| ------ | ----------------- | ---------------------- | ----------------------------- | ------------------------------------ |
| GET    | `/global/health`  | `global.health`        | —                             | `{ healthy: true, version: string }` |
| GET    | `/global/event`   | `global.event`         | —                             | SSE stream (see §3)                  |
| GET    | `/global/config`  | `global.config.get`    | —                             | `Config.Global`                      |
| PATCH  | `/global/config`  | `global.config.update` | Body: partial `Config.Global` | `Config.Global`                      |
| POST   | `/global/dispose` | `global.dispose`       | —                             | 200                                  |

### Top-Level Routes

| Method | Path                | Operation          | Request                    | Response                                               |
| ------ | ------------------- | ------------------ | -------------------------- | ------------------------------------------------------ |
| GET    | `/doc`              | —                  | —                          | OpenAPI JSON spec                                      |
| GET    | `/event`            | `event.subscribe`  | Requires workspace context | SSE stream (see §3)                                    |
| GET    | `/path`             | `path.get`         | —                          | `{ home, state, config, worktree, directory: string }` |
| GET    | `/vcs`              | `vcs.get`          | —                          | `{ branch?: string }`                                  |
| GET    | `/command`          | `command.list`     | —                          | `Command[]`                                            |
| POST   | `/log`              | `app.log`          | Body: log data             | 200 (no workspace needed)                              |
| GET    | `/agent`            | `app.agents`       | —                          | `Agent.Info[]`                                         |
| GET    | `/skill`            | `app.skills`       | —                          | `Skill.Info[]`                                         |
| GET    | `/lsp`              | `lsp.status`       | —                          | LSP status                                             |
| GET    | `/formatter`        | `formatter.status` | —                          | Formatter status                                       |
| POST   | `/instance/dispose` | `instance.dispose` | —                          | 200                                                    |

### Auth Routes

| Method | Path                | Operation     | Request           | Response |
| ------ | ------------------- | ------------- | ----------------- | -------- |
| PUT    | `/auth/:providerID` | `auth.set`    | Body: `Auth.Info` | 200      |
| DELETE | `/auth/:providerID` | `auth.remove` | —                 | 200      |

### Session Routes

| Method | Path                                                  | Operation               | Request                                              | Response                                              |
| ------ | ----------------------------------------------------- | ----------------------- | ---------------------------------------------------- | ----------------------------------------------------- |
| GET    | `/session/`                                           | `session.list`          | Query: `directory?, roots?, start?, search?, limit?` | `Session.Info[]`                                      |
| GET    | `/session/status`                                     | `session.status`        | —                                                    | `Record<string, SessionStatus.Info>`                  |
| GET    | `/session/:sessionID`                                 | `session.get`           | —                                                    | `Session.Info`                                        |
| POST   | `/session/`                                           | `session.create`        | Body: `{}` or `{ title?, parentID? }`                | `Session.Info`                                        |
| DELETE | `/session/:sessionID`                                 | `session.delete`        | —                                                    | 200                                                   |
| PATCH  | `/session/:sessionID`                                 | `session.update`        | Body: `{ title?, time?: { archived?: number } }`     | `Session.Info`                                        |
| POST   | `/session/:sessionID/init`                            | `session.init`          | Body: `{}`                                           | `Session.Info`                                        |
| POST   | `/session/:sessionID/fork`                            | `session.fork`          | Body: `{ messageID: string }`                        | `Session.Info`                                        |
| POST   | `/session/:sessionID/abort`                           | `session.abort`         | —                                                    | 200                                                   |
| POST   | `/session/:sessionID/share`                           | `session.share`         | —                                                    | `{ url: string }`                                     |
| DELETE | `/session/:sessionID/share`                           | `session.unshare`       | —                                                    | 200                                                   |
| GET    | `/session/:sessionID/diff`                            | `session.diff`          | Query: `messageID`                                   | `FileDiff[]`                                          |
| GET    | `/session/:sessionID/children`                        | `session.children`      | —                                                    | `Session.Info[]`                                      |
| GET    | `/session/:sessionID/todo`                            | `session.todo`          | —                                                    | `Todo.Info[]`                                         |
| POST   | `/session/:sessionID/summarize`                       | `session.summarize`     | Body: `{ providerID, modelID, auto? }`               | 200                                                   |
| GET    | `/session/:sessionID/message`                         | `session.messages`      | Query: `limit?`                                      | `{ info: MessageV2.Info, parts: MessageV2.Part[] }[]` |
| GET    | `/session/:sessionID/message/:messageID`              | `session.message`       | —                                                    | `{ info: MessageV2.Info, parts: MessageV2.Part[] }`   |
| DELETE | `/session/:sessionID/message/:messageID`              | `session.deleteMessage` | —                                                    | 200                                                   |
| DELETE | `/session/:sessionID/message/:messageID/part/:partID` | `part.delete`           | —                                                    | 200                                                   |
| PATCH  | `/session/:sessionID/message/:messageID/part/:partID` | `part.update`           | Body: part update                                    | Updated part                                          |
| POST   | `/session/:sessionID/message`                         | `session.prompt`        | Body: `PromptInput`                                  | Stream → `{ info, parts }`                            |
| POST   | `/session/:sessionID/prompt_async`                    | `session.prompt_async`  | Body: `PromptInput`                                  | 204 (no body)                                         |
| POST   | `/session/:sessionID/command`                         | `session.command`       | Body: `{ name, arguments?, messageID? }`             | 204                                                   |
| POST   | `/session/:sessionID/shell`                           | `session.shell`         | Body: `{ command }`                                  | 200                                                   |
| POST   | `/session/:sessionID/revert`                          | `session.revert`        | Body: `{ messageID, partID?, snapshot? }`            | 200                                                   |
| POST   | `/session/:sessionID/unrevert`                        | `session.unrevert`      | —                                                    | 200                                                   |

### Project Routes

| Method | Path                  | Operation         | Request                      | Response         |
| ------ | --------------------- | ----------------- | ---------------------------- | ---------------- |
| GET    | `/project/`           | `project.list`    | —                            | `Project.Info[]` |
| GET    | `/project/current`    | `project.current` | —                            | `Project.Info`   |
| PATCH  | `/project/:projectID` | `project.update`  | Body: partial `Project.Info` | `Project.Info`   |

### Config Routes

| Method | Path                | Operation          | Request                     | Response             |
| ------ | ------------------- | ------------------ | --------------------------- | -------------------- |
| GET    | `/config/`          | `config.get`       | —                           | `Config.Info`        |
| PATCH  | `/config/`          | `config.update`    | Body: partial `Config.Info` | `Config.Info`        |
| GET    | `/config/providers` | `config.providers` | —                           | Provider config list |

### Provider Routes

| Method | Path                                    | Operation                  | Request            | Response                                |
| ------ | --------------------------------------- | -------------------------- | ------------------ | --------------------------------------- |
| GET    | `/provider/`                            | `provider.list`            | —                  | `Provider.Info[]`                       |
| GET    | `/provider/auth`                        | `provider.auth`            | —                  | `Record<string, ProviderAuth.Method[]>` |
| POST   | `/provider/:providerID/oauth/authorize` | `provider.oauth.authorize` | Body: `{ method }` | `ProviderAuth.Authorization`            |
| POST   | `/provider/:providerID/oauth/callback`  | `provider.oauth.callback`  | Body: `{ code }`   | 200                                     |

### File & Search Routes

| Method | Path            | Operation      | Request                              | Response              |
| ------ | --------------- | -------------- | ------------------------------------ | --------------------- |
| GET    | `/find`         | `find.text`    | Query: `pattern`                     | Search results        |
| GET    | `/find/file`    | `find.files`   | Query: `query, dirs?, type?, limit?` | File matches          |
| GET    | `/find/symbol`  | `find.symbols` | —                                    | `[]` (currently stub) |
| GET    | `/file`         | `file.list`    | Query: `path`                        | `File.Node[]`         |
| GET    | `/file/content` | `file.read`    | Query: `path`                        | `File.Content`        |
| GET    | `/file/status`  | `file.status`  | —                                    | `File.Info[]`         |

### MCP Routes

| Method | Path                           | Operation               | Request          | Response                     |
| ------ | ------------------------------ | ----------------------- | ---------------- | ---------------------------- |
| GET    | `/mcp/`                        | `mcp.status`            | —                | `Record<string, MCP.Status>` |
| POST   | `/mcp/`                        | `mcp.add`               | Body: MCP config | 200                          |
| POST   | `/mcp/:name/connect`           | `mcp.connect`           | —                | 200                          |
| POST   | `/mcp/:name/disconnect`        | `mcp.disconnect`        | —                | 200                          |
| POST   | `/mcp/:name/auth`              | `mcp.auth.start`        | —                | `{ url }`                    |
| POST   | `/mcp/:name/auth/callback`     | `mcp.auth.callback`     | Body: `{ code }` | 200                          |
| POST   | `/mcp/:name/auth/authenticate` | `mcp.auth.authenticate` | Body: `{ key }`  | 200                          |
| DELETE | `/mcp/:name/auth`              | `mcp.auth.remove`       | —                | 200                          |

### PTY Routes

| Method | Path                  | Operation     | Request                 | Response              |
| ------ | --------------------- | ------------- | ----------------------- | --------------------- |
| GET    | `/pty/`               | `pty.list`    | —                       | `Pty.Info[]`          |
| POST   | `/pty/`               | `pty.create`  | Body: `Pty.CreateInput` | `Pty.Info`            |
| GET    | `/pty/:ptyID`         | `pty.get`     | —                       | `Pty.Info`            |
| PUT    | `/pty/:ptyID`         | `pty.update`  | Body: `Pty.UpdateInput` | `Pty.Info`            |
| DELETE | `/pty/:ptyID`         | `pty.remove`  | —                       | 200                   |
| GET    | `/pty/:ptyID/connect` | `pty.connect` | —                       | **WebSocket upgrade** |

### Permission Routes

| Method | Path                           | Operation          | Request                                           | Response                   |
| ------ | ------------------------------ | ------------------ | ------------------------------------------------- | -------------------------- |
| GET    | `/permission/`                 | `permission.list`  | —                                                 | `PermissionNext.Request[]` |
| POST   | `/permission/:requestID/reply` | `permission.reply` | Body: `{ reply: "once" \| "always" \| "reject" }` | 200                        |

### Question Routes

| Method | Path                          | Operation         | Request                         | Response             |
| ------ | ----------------------------- | ----------------- | ------------------------------- | -------------------- |
| GET    | `/question/`                  | `question.list`   | —                               | `Question.Request[]` |
| POST   | `/question/:requestID/reply`  | `question.reply`  | Body: `{ answers: string[][] }` | 200                  |
| POST   | `/question/:requestID/reject` | `question.reject` | —                               | 200                  |

### Experimental Routes

| Method | Path                           | Operation                    | Request                  | Response                  |
| ------ | ------------------------------ | ---------------------------- | ------------------------ | ------------------------- |
| GET    | `/experimental/tool/ids`       | `tool.ids`                   | —                        | `string[]`                |
| GET    | `/experimental/tool`           | `tool.list`                  | —                        | Tool list                 |
| POST   | `/experimental/worktree`       | `worktree.create`            | Body: `{ name }`         | 200                       |
| GET    | `/experimental/worktree`       | `worktree.list`              | —                        | Worktree list             |
| DELETE | `/experimental/worktree`       | `worktree.remove`            | Query: `name`            | 200                       |
| POST   | `/experimental/worktree/reset` | `worktree.reset`             | Body: `{ name }`         | 200                       |
| GET    | `/experimental/session`        | `experimental.session.list`  | Query: `cursor?, limit?` | Cursor-paginated sessions |
| GET    | `/experimental/resource`       | `experimental.resource.list` | —                        | `MCP.Resource[]`          |
| GET    | `/experimental/workspace/`     | `workspace.list`             | —                        | Workspace list            |
| POST   | `/experimental/workspace/:id`  | `workspace.create`           | —                        | 200                       |
| DELETE | `/experimental/workspace/:id`  | `workspace.remove`           | —                        | 200                       |

### TUI Routes (NOT needed for iOS)

13 routes under `/tui/` for terminal UI control — `append-prompt`, `submit-prompt`, `open-help`, etc. **Skip these for iOS.**

---

## 5. Wire-Format Schemas

### Session.Info

```json
{
  "id": "ses_...",
  "slug": "string",
  "projectID": "string",
  "workspaceID": "string?",
  "directory": "string",
  "parentID": "string?",
  "title": "string",
  "version": "string",
  "summary": {
    "additions": 0,
    "deletions": 0,
    "files": 0,
    "diffs": [
      { "file": "", "before": "", "after": "", "additions": 0, "deletions": 0, "status": "added|deleted|modified" }
    ]
  },
  "share": { "url": "string" },
  "revert": {
    "messageID": "string",
    "partID": "string?",
    "snapshot": "string?",
    "diff": "string?"
  },
  "permission": [{ "permission": "", "pattern": "", "action": "allow|deny|ask" }],
  "time": {
    "created": 1234567890,
    "updated": 1234567890,
    "compacting": 1234567890,
    "archived": 1234567890
  }
}
```

### SessionStatus.Info (discriminated union on `type`)

```json
{ "type": "idle" }
{ "type": "busy" }
{ "type": "retry", "attempt": 1, "message": "Rate limited", "next": 1234567890 }
```

### MessageV2.Info — User

```json
{
  "id": "msg_...",
  "sessionID": "ses_...",
  "role": "user",
  "time": { "created": 1234567890 },
  "format": "string?",
  "summary": { "title": "string?", "body": "string?", "diffs": [] },
  "agent": "string",
  "model": { "providerID": "string", "modelID": "string" },
  "system": "string?",
  "tools": { "toolName": true },
  "variant": "string?"
}
```

### MessageV2.Info — Assistant

```json
{
  "id": "msg_...",
  "sessionID": "ses_...",
  "role": "assistant",
  "time": { "created": 1234567890, "completed": 1234567890 },
  "error": null,
  "parentID": "string",
  "modelID": "string",
  "providerID": "string",
  "mode": "string",
  "agent": "string",
  "path": { "cwd": "string", "root": "string" },
  "summary": false,
  "cost": 0.0,
  "tokens": {
    "total": 0,
    "input": 0,
    "output": 0,
    "reasoning": 0,
    "cache": { "read": 0, "write": 0 }
  },
  "structured": null,
  "variant": "string?",
  "finish": "string?"
}
```

### MessageV2.Info — Assistant Error Types

The `error` field on assistant messages is a discriminated union:

| Error Type          | Key Fields              |
| ------------------- | ----------------------- |
| `auth`              | `providerID, message`   |
| `unknown`           | `message, stack?`       |
| `output_length`     | `message`               |
| `aborted`           | `message`               |
| `structured_output` | `message`               |
| `context_overflow`  | `message, max, current` |
| `api`               | `status, body, message` |

### MessageV2.Part (discriminated union on `type`)

All parts have base: `{ id, sessionID, messageID: string }`

#### `text`

```json
{
  "type": "text",
  "text": "Hello world...",
  "synthetic": false,
  "ignored": false,
  "time": { "start": 1234567890, "end": 1234567890 },
  "metadata": {}
}
```

#### `reasoning`

```json
{
  "type": "reasoning",
  "text": "Let me think...",
  "metadata": {},
  "time": { "start": 1234567890, "end": 1234567890 }
}
```

#### `file`

```json
{
  "type": "file",
  "mime": "image/png",
  "filename": "screenshot.png",
  "url": "data:image/png;base64,...",
  "source": { "type": "...", ... }
}
```

#### `tool`

```json
{
  "type": "tool",
  "callID": "call_...",
  "tool": "file_edit",
  "state": { ... },
  "metadata": {}
}
```

#### `step-start`

```json
{ "type": "step-start", "snapshot": "string?" }
```

#### `step-finish`

```json
{
  "type": "step-finish",
  "reason": "stop|tool_use|max_tokens",
  "snapshot": "string?",
  "cost": 0.0,
  "tokens": { "total": 0, "input": 0, "output": 0, "reasoning": 0, "cache": { "read": 0, "write": 0 } }
}
```

#### `snapshot`

```json
{ "type": "snapshot", "snapshot": "string" }
```

#### `patch`

```json
{ "type": "patch", "hash": "string", "files": ["path/to/file"] }
```

#### `agent`

```json
{ "type": "agent", "name": "string", "source": { "value": "", "start": 0, "end": 0 } }
```

#### `subtask`

```json
{
  "type": "subtask",
  "prompt": "string",
  "description": "string",
  "agent": "string",
  "model": { "providerID": "string", "modelID": "string" },
  "command": "string?"
}
```

#### `retry`

```json
{
  "type": "retry",
  "attempt": 1,
  "error": { "type": "api", "status": 429, "body": "...", "message": "..." },
  "time": { "created": 1234567890 }
}
```

#### `compaction`

```json
{ "type": "compaction", "auto": true, "overflow": false }
```

### ToolState (discriminated union on `status`)

#### `pending`

```json
{ "status": "pending", "input": {}, "raw": "string" }
```

#### `running`

```json
{
  "status": "running",
  "input": {},
  "title": "Reading file...",
  "metadata": {},
  "time": { "start": 1234567890 }
}
```

#### `completed`

```json
{
  "status": "completed",
  "input": {},
  "output": "file contents...",
  "title": "Read file.ts",
  "metadata": {},
  "time": { "start": 1234567890, "end": 1234567890, "compacted": 1234567890 },
  "attachments": []
}
```

#### `error`

```json
{
  "status": "error",
  "input": {},
  "error": "Permission denied",
  "metadata": {},
  "time": { "start": 1234567890, "end": 1234567890 }
}
```

### PromptInput (request body for `POST /session/:sessionID/message`)

```json
{
  "sessionID": "ses_...",
  "messageID": "msg_...",
  "model": { "providerID": "anthropic", "modelID": "claude-sonnet-4-20250514" },
  "agent": "code",
  "noReply": false,
  "tools": { "file_edit": true },
  "format": "string?",
  "system": "string?",
  "variant": "string?",
  "parts": [
    { "type": "text", "text": "Hello!" },
    { "type": "file", "mime": "image/png", "url": "data:...", "filename": "img.png" },
    { "type": "agent", "name": "code", "source": { "value": "", "start": 0, "end": 0 } },
    { "type": "subtask", "prompt": "...", "description": "...", "agent": "code" }
  ]
}
```

**Key fields**:

- `parts`: Array of input parts — at minimum one `text` part
- `model`: Optional override for provider/model
- `agent`: Optional agent name override
- `noReply`: If true, only sends user message, no assistant response
- `messageID`: If set, edits/retries from that message

### PermissionNext.Request

```json
{
  "id": "perm_...",
  "sessionID": "ses_...",
  "permission": "file.write",
  "patterns": ["/path/to/file.ts"],
  "metadata": { "tool": "file_edit" },
  "always": ["allow", "deny"],
  "tool": { "messageID": "msg_...", "callID": "call_..." }
}
```

### PermissionNext.Reply

```json
"once" | "always" | "reject"
```

Reply via: `POST /permission/:requestID/reply` with body `{ "reply": "once" }`

### Question.Request

```json
{
  "id": "question_...",
  "sessionID": "ses_...",
  "questions": [
    {
      "question": "Which framework do you prefer?",
      "header": "Framework Choice",
      "options": [
        { "label": "React", "description": "Component-based UI library" },
        { "label": "Vue", "description": "Progressive framework" }
      ],
      "multiple": false,
      "custom": true
    }
  ],
  "tool": { "messageID": "msg_...", "callID": "call_..." }
}
```

### Question.Reply

```json
{ "answers": [["React"]] }
```

`answers[i]` contains the selected label(s) for `questions[i]`. Reply via `POST /question/:requestID/reply`.

### Project.Info

```json
{
  "id": "string",
  "worktree": "/path/to/project",
  "vcs": "git",
  "name": "my-project",
  "icon": { "url": "string?", "override": "string?", "color": "string?" },
  "commands": { "start": "bun dev" },
  "time": { "created": 0, "updated": 0, "initialized": 0 },
  "sandboxes": []
}
```

### Provider.Info

```json
{
  "id": "anthropic",
  "name": "Anthropic",
  "source": "env|config|custom|api",
  "env": ["ANTHROPIC_API_KEY"],
  "key": "string?",
  "options": {},
  "models": {
    "claude-sonnet-4-20250514": {
      "id": "claude-sonnet-4-20250514",
      "providerID": "anthropic",
      "api": { "id": "anthropic", "url": "https://api.anthropic.com/v1", "npm": "@ai-sdk/anthropic" },
      "name": "Claude Sonnet 4",
      "family": "claude",
      "capabilities": {
        "temperature": true,
        "reasoning": false,
        "attachment": true,
        "toolcall": true,
        "input": { "text": true, "audio": false, "image": true, "video": false, "pdf": true },
        "output": { "text": true, "audio": false, "image": false, "video": false },
        "interleaved": true
      },
      "cost": { "input": 3, "output": 15, "cache": { "read": 0.3, "write": 3.75 } },
      "limit": { "context": 200000, "output": 16000 },
      "status": "active",
      "options": {},
      "headers": {},
      "release_date": "2025-05-14"
    }
  }
}
```

### Auth.Info (discriminated union on `type`)

```json
{ "type": "oauth", "refresh": "...", "access": "...", "expires": 1234567890, "accountId": "string?", "enterpriseUrl": "string?" }
{ "type": "api", "key": "sk-..." }
{ "type": "wellknown", "key": "...", "token": "..." }
```

### File Schemas

#### File.Node

```json
{
  "name": "file.ts",
  "path": "src/file.ts",
  "absolute": "/full/path/src/file.ts",
  "type": "file|directory",
  "ignored": false
}
```

#### File.Content

```json
{
  "type": "text|binary",
  "content": "file contents or base64...",
  "diff": "unified diff string?",
  "patch": {
    "oldFileName": "a/file.ts",
    "newFileName": "b/file.ts",
    "hunks": [
      { "oldStart": 1, "oldLines": 10, "newStart": 1, "newLines": 12, "lines": ["+added", "-removed", " context"] }
    ]
  },
  "encoding": "base64?",
  "mimeType": "text/typescript?"
}
```

#### File.Info (git status)

```json
{ "path": "src/file.ts", "added": 5, "removed": 2, "status": "added|deleted|modified" }
```

### Pty Schemas

#### Pty.Info

```json
{
  "id": "pty_...",
  "title": "bash",
  "command": "/bin/bash",
  "args": [],
  "cwd": "/path",
  "status": "running|exited",
  "pid": 12345
}
```

#### Pty.CreateInput

```json
{ "command": "/bin/bash", "args": ["-l"], "cwd": "/path", "title": "My Terminal", "env": { "FOO": "bar" } }
```

#### Pty.UpdateInput

```json
{ "title": "New Title", "size": { "rows": 24, "cols": 80 } }
```

### Todo.Info

```json
{ "content": "Fix login bug", "status": "pending|in_progress|completed|cancelled", "priority": "high|medium|low" }
```

### Agent.Info

```json
{
  "name": "code",
  "description": "Primary coding agent",
  "mode": "primary|subagent|all",
  "native": true,
  "hidden": false,
  "topP": 0.9,
  "temperature": 0.7,
  "color": "#FF0000",
  "permission": [{ "permission": "file.write", "pattern": "**", "action": "ask" }],
  "model": { "modelID": "claude-sonnet-4-20250514", "providerID": "anthropic" },
  "variant": "string?",
  "prompt": "string?",
  "options": {},
  "steps": 100
}
```

### Skill.Info

```json
{
  "name": "playwright",
  "description": "Browser automation...",
  "location": "/path/to/skill",
  "content": "# Skill content..."
}
```

### MCP.Status (discriminated union on `status`)

```json
{ "status": "connected" }
{ "status": "disabled" }
{ "status": "failed", "error": "Connection refused" }
{ "status": "needs_auth" }
{ "status": "needs_client_registration", "error": "..." }
```

### Snapshot.FileDiff

```json
{
  "file": "src/main.ts",
  "before": "old hash",
  "after": "new hash",
  "additions": 5,
  "deletions": 2,
  "status": "modified"
}
```

---

## 6. Streaming & Prompt Patterns

### CRITICAL: How Prompting Actually Works

There are **two ways** to send a prompt:

#### Option A: Synchronous Prompt (`POST /session/:sessionID/message`)

- **Request**: Body is `PromptInput` JSON
- **Response**: Uses Hono `stream()` — this is a **raw byte stream**, NOT SSE
- **Content-Type**: `application/json` (despite being streamed)
- **Behavior**: The response body is a **single JSON object** `{ info: MessageV2.Info, parts: MessageV2.Part[] }` written when the prompt loop completes
- **Real-time updates**: Come via the **SSE `/event` stream**, NOT this response
- **When it completes**: The connection closes after writing the final JSON

**iOS Pattern**: Send the POST, but don't rely on it for real-time UI updates. Listen to SSE events (`message.part.updated`, `message.part.delta`) for streaming text, tool progress, etc. The POST response gives you the final result.

#### Option B: Async Prompt (`POST /session/:sessionID/prompt_async`)

- **Request**: Same `PromptInput` body
- **Response**: Returns `204 No Content` immediately
- **Behavior**: Prompt runs entirely in background
- **Real-time updates**: 100% via SSE events

**iOS Recommendation**: Use `prompt_async` — it's simpler. Fire and forget, rely on SSE for everything.

### Event Flow During a Prompt

When a prompt runs, SSE events arrive in roughly this order:

```
1. session.status        → { type: "busy" }
2. message.updated       → User message created
3. message.part.updated  → step-start part
4. message.part.updated  → text part (initial)
5. message.part.delta    → { field: "text", delta: "streaming..." } (repeated)
6. message.part.updated  → tool part (pending → running → completed)
7. message.part.updated  → step-finish part
8. message.updated       → Assistant message (with tokens, cost)
9. session.status        → { type: "idle" }
10. session.updated      → Session metadata (title may change)
```

**Key insight**: `message.part.delta` events give you **incremental text** — apply the `delta` string by appending to the existing part's `text` field. This is the most efficient way to stream text to the UI.

### Aborting a Prompt

`POST /session/:sessionID/abort` — stops the currently running prompt. The assistant message will have `error: { type: "aborted" }`.

---

## 7. WebSocket (PTY Only)

WebSocket is used **only** for PTY terminal connections:

```
GET /pty/:ptyID/connect → WebSocket upgrade
```

- **Protocol**: Raw binary frames (terminal I/O)
- **Send**: User keystrokes as binary data
- **Receive**: Terminal output as binary data

**iOS consideration**: Only needed if your app supports embedded terminal views. Most iOS apps can skip PTY entirely.

---

## 8. OpenAPI Spec Gap Analysis

The static OpenAPI spec (`packages/sdk/openapi.json`) has significant gaps vs the actual server:

### Completely Missing Route Files (~40+ routes)

| Route File            | Routes    | Status in Spec                            |
| --------------------- | --------- | ----------------------------------------- |
| `file.ts`             | 6 routes  | **100% missing**                          |
| `provider.ts`         | 4 routes  | **100% missing**                          |
| `question.ts`         | 3 routes  | **100% missing**                          |
| `permission.ts` (new) | 2 routes  | **100% missing**                          |
| `tui.ts`              | 13 routes | **100% missing** (but not needed for iOS) |

### Partially Missing Routes

| Route File        | Total | Documented | Missing                                                                                                 |
| ----------------- | ----- | ---------- | ------------------------------------------------------------------------------------------------------- |
| `session.ts`      | 24    | ~16        | `prompt_async`, `revert`, `unrevert`, `shell`, `command`, `deleteMessage`, `part.delete`, `part.update` |
| `mcp.ts`          | 8     | 1          | All auth, connect, disconnect, add routes                                                               |
| `experimental.ts` | 11    | ~3         | Most experimental routes                                                                                |

### Schema Issues in Spec

- `ToolStatePending` and `ToolStateRunning`: Listed with **no properties** — actual schemas have `input`, `raw`, `title`, `metadata`, `time`
- `AgentPart.source`: Empty object — actually `{ value, start, end }`
- `StepFinishPart.tokens.cache`: Empty — actually `{ read, write }`
- Several `additionalProperties: {}` without real type definitions
- `FilePartSource` not fully specified

**iOS Implication**: If you generated Swift types from `openapi.json`, they are **incomplete**. Use the schemas in §5 above as the source of truth.

---

## 9. iOS App Checklist — Gaps & Corrections

### ✅ Must-Have Features

- [ ] **Workspace context on every request** — `workspace` + `directory` query params or headers
- [ ] **SSE event stream** — Connect to `GET /event` on app launch, handle reconnection
- [ ] **Permission handling** — Listen for `permission.asked` events, show UI, reply via `POST /permission/:requestID/reply`
- [ ] **Question handling** — Listen for `question.asked` events, show selection UI, reply via `POST /question/:requestID/reply`
- [ ] **Session status tracking** — Handle `session.status` events for busy/idle/retry states
- [ ] **Async prompt** — Use `POST /session/:sessionID/prompt_async` (simpler than sync)
- [ ] **Delta text streaming** — Handle `message.part.delta` for efficient text updates (append `delta` to existing part text)
- [ ] **Session abort** — `POST /session/:sessionID/abort` to cancel running prompts
- [ ] **All MessageV2.Part types** — Handle all 12 part types in the chat UI

### 🔍 Likely Missing Endpoints

Based on the OpenAPI spec gaps, your iOS app probably doesn't implement:

| Endpoint                                        | Why It Matters                   |
| ----------------------------------------------- | -------------------------------- |
| `POST /session/:sessionID/prompt_async`         | Simpler prompt flow, returns 204 |
| `POST /session/:sessionID/revert`               | Undo file changes from a message |
| `POST /session/:sessionID/unrevert`             | Re-apply reverted changes        |
| `POST /session/:sessionID/shell`                | Run shell commands in session    |
| `POST /session/:sessionID/command`              | Execute slash commands           |
| `DELETE /session/:sessionID/message/:messageID` | Delete a message                 |
| `DELETE .../part/:partID`                       | Delete a message part            |
| `PATCH .../part/:partID`                        | Update a message part            |
| `GET /file`                                     | List directory contents          |
| `GET /file/content`                             | Read file content                |
| `GET /file/status`                              | Git status of files              |
| `GET /find`                                     | Full-text search                 |
| `GET /find/file`                                | File name search                 |
| `GET /provider/`                                | List providers with models       |
| `GET /provider/auth`                            | Auth methods per provider        |
| `POST /provider/:id/oauth/authorize`            | Start OAuth flow                 |
| `POST /provider/:id/oauth/callback`             | Complete OAuth flow              |
| `GET /question/`                                | List pending questions           |
| `POST /question/:id/reply`                      | Answer a question                |
| `POST /question/:id/reject`                     | Reject a question                |
| `GET /permission/`                              | List pending permissions         |
| `POST /permission/:id/reply`                    | Reply to permission              |
| `POST /session/:sessionID/fork`                 | Fork session at message          |
| `POST /session/:sessionID/share`                | Share session publicly           |
| `GET /session/:sessionID/diff`                  | Get file diffs for message       |
| `GET /session/:sessionID/todo`                  | Get session todo list            |
| `POST /session/:sessionID/summarize`            | Generate session summary         |

### 🔧 Likely Schema Corrections Needed

If you generated models from the OpenAPI spec:

1. **ToolState.pending** — Add `input: [String: Any]` and `raw: String`
2. **ToolState.running** — Add `input`, `title?`, `metadata?`, `time: { start }`
3. **AgentPart.source** — Change from empty to `{ value: String, start: Int, end: Int }`
4. **StepFinishPart.tokens.cache** — Add `{ read: Int, write: Int }`
5. **Add missing part types**: `retry`, `compaction`, `subtask`, `patch`
6. **Add `message.part.delta` event type** — Critical for streaming
7. **Add `session.status` event** with `SessionStatus.Info` union type
8. **File.Content** — Add `patch` object with hunks, `encoding`, `mimeType`
9. **Session.Info** — Add `permission`, `revert`, `share`, `summary` fields
10. **MessageV2.Info (assistant)** — Add full `error` discriminated union with all 7 types

### 🎯 Priority Implementation Order

If building incrementally:

1. **P0 — Core Loop**: SSE events + `prompt_async` + `session.status` + `message.part.delta`
2. **P0 — Blockers**: `permission.reply` + `question.reply` (agent hangs without these)
3. **P1 — Session Management**: List, create, delete, update, abort, fork
4. **P1 — File Viewing**: `file.list`, `file.read`, `file.status` for diff/change viewing
5. **P2 — Provider Management**: List providers, auth methods, OAuth flow
6. **P2 — Advanced Session**: Revert/unrevert, share, diff, summarize, todo
7. **P3 — Search**: `find.text`, `find.file`
8. **P3 — MCP Management**: Status, connect/disconnect, auth
9. **P4 — Experimental**: Tools list, worktrees, workspaces

---

_Generated from source code analysis of `packages/opencode/src/server/` — all schemas extracted from Zod definitions, not from the incomplete OpenAPI spec._
