> [!IMPORTANT]
> This repo is a placeholder for now. The real source code lands here once the
> project hits **10,000 stars**. The releases and installers below are the
> actual product.

[![SlopOn product introduction video](images/thumbnail6.png)](https://youtu.be/nW0YdV7NyII)

## What is SlopOn?

A desktop agentic coding environment. You attach one or more repos to a project, set up bots (agents), and chat with them to plan, write, run, and review code. The point of the app is everything wrapped around the model: tasks, a phase pipeline, a git worktree per task, prompt templates, tool permissions, and a human approving anything sensitive before it happens.

It's a thin Flutter client talking over WebSocket to a separate backend that does the LLM calls, git operations, and tool execution. The backend runs on your machine or on some other box entirely, the client doesn't care.

## Features

- Human in the loop: tool calls that need consent turn into approval prompts, bots can ask you questions mid-task, and per-project tool permissions decide what's auto-approved and what waits for your click.
- Tasks and a phase pipeline. Each phase carries a prompt template, so the prompt for the next step comes out generated and ready to run (or edit first).
- One git worktree per task: isolated branch, diff against main, merge when you're happy, tear it down when done.
- Context compaction: chat history gets summarized (auto or manual) once usage crosses a threshold you set, so long sessions stay coherent instead of degrading into mush.
- Token stats: live used vs total context, with input/output/cache breakdown.
- Multiple source folders per project.
- Multiple bots per project with different models, system prompts, and toolsets. Bots can delegate scoped sub-tasks to other bots, and there's an advisor tool for a second opinion from another LLM.
- No provider lock-in: OpenAI-compatible and Anthropic providers, custom base URLs, local and self-hosted models included.
- MCP servers over SSE or HTTP, per project, and their tools become available to your bots.
- LSP integration: go-to-definition and find-references, so bots navigate code semantically like an IDE would.
- Reusable and quick prompts, each runnable with the bot you pick.
- Remote backend: point the client at a backend running somewhere else.
- The client stays light on memory: it renders and orchestrates, the backend does the heavy lifting.
- Native builds for Windows, macOS, and Debian Linux.

## Install

One-liner, per-user, no admin:

macOS (Apple Silicon and Intel) and Debian Linux x64:

```sh
curl -fsSL https://slopon.dev/install.sh | sh
```

Windows x64 (Windows PowerShell):

```powershell
powershell -NoProfile -c "irm https://slopon.dev/install.ps1 | iex"
```

Then launch SlopOn from your applications folder / Start Menu / app menu. To upgrade, close the app and the backend and run the same command again. Your `~/.slopon` (config, database, attachments) is left alone.

### Manual install

Rather do it by hand? Same releases, more steps:

1. Download the archive for your platform from the [releases page](https://github.com/DigiDecode/SlopOn.dev/releases): `slopon-windows-x64.zip`, `slopon-linux-x64.tar.gz`, or `slopon-macos-arm64.zip` / `slopon-macos-x64.zip` (arm64 for Apple Silicon, x64 for Intel).
2. Extract it. You get three folders: `frontend/` (the desktop app), `backend/` (the Node.js server), and `launcher/` (the one-command start helper).
3. Install the backend dependencies from the shipped lockfile:

   ```sh
   cd backend
   npm ci
   ```

   You want Node.js 20 or 22 on your PATH (later majors aren't verified yet) and git. On Linux, `chmod +x frontend/slopon_dev` if the binary lost its exec bit during extraction.

4. Start it with the launcher: `./launcher/slopon.sh` on macOS/Linux, `launcher\slopon.cmd` on Windows. It starts the backend, waits until it's actually listening, then opens the app. Running it twice doesn't spawn a second backend. `--stop` stops the backend again.

On first start the backend generates an API key and prints it in a banner. The app reads the same `~/.slopon/config.json`, so with the launcher you never type the key. Starting the frontend by hand instead? Enter it when the app asks.

More detail (logs under `~/.slopon/logs/`, the classic `node index.js` path, unsigned-build warnings) in [`docs/release-README.md`](docs/release-README.md).

## License

Free for individuals and for organizations under USD 100,000 aggregate gross revenue (trailing 12 months). Above that you need a commercial license. Whatever the bots generate from your inputs is yours. Plain-language summary in [LICENSING.md](license/LICENSING.md), full terms in [LICENSE.md](license/LICENSE.md).

## Development workspace

The `setup.sh` / `setup.bat` scripts in this repo clone and sync the project's dev repositories, if you're helping out. See [`docs/workspace-setup.md`](docs/workspace-setup.md).
