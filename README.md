> [!IMPORTANT]
> The source code isn't here yet. It shows up once the project hits
> **10,000 stars**. The releases and installers below are the real product
> meanwhile.

[![SlopOn product introduction video](images/thumbnail6.png)](https://youtu.be/nW0YdV7NyII)

## SlopOn

SlopOn is a desktop agentic coding environment. Here's how a project goes.

It starts with repos and work that needs doing in them. You make a project, attach the repos (one or a whole handful, whatever the job needs), and set up your bots.

The bots are where it gets fun. Each one gets its own model, its own system prompt, its own toolset. One can be the planner on a big model, another the workhorse on something cheap and local, because there's no provider lock-in: anything OpenAI-compatible, anything Anthropic, any custom base URL, self-hosted included. When a bot wants a sanity check it can delegate a scoped sub-task to another bot, or call the advisor tool and get a second opinion from a different LLM.

Then you create a task and the process kicks in. Tasks move through a pipeline of phases, every phase carries a prompt template, so the prompt for the next step comes out written for you, ready to run or edit first. The task gets its own git worktree on its own branch, so the bot can flail around in isolation. When the dust settles you diff against main, merge if you're happy, tear the worktree down, move on.

Meanwhile the bot isn't just chatting. It reads code semantically (go-to-definition, find-references, LSP-style, the way an IDE would), runs things, calls tools. Anything sensitive hits a wall: tool calls that need consent turn into approval prompts, the bot can ask you questions mid-task, and per-project tool permissions decide what's auto-approved and what waits for your click. You're the boss, it does the work.

Long sessions don't rot either. When context usage crosses a threshold you set, the history gets summarized, automatically or on demand, and a live token meter shows used vs total with an input/output/cache breakdown, so you always know how much room is left. MCP users: connect servers per project over SSE or HTTP and their tools show up for your bots too.

Under the hood it's two programs. A thin Flutter desktop client that renders and stays light on memory, and a backend that does the actual heavy lifting: LLM calls, git operations, tool execution. They talk over WebSocket. The backend can sit on your machine or on some other box entirely, the client doesn't care. Native builds for Windows, macOS, and Debian Linux.

## Quick one liner install

The short version, one line, per-user, no admin:

macOS (Apple Silicon and Intel) and Debian Linux x64:

```sh
curl -fsSL https://slopon.dev/install.sh | sh
```

Windows x64 (Windows PowerShell):

```powershell
powershell -NoProfile -c "irm https://slopon.dev/install.ps1 | iex"
```

When it's done, SlopOn shows up in your applications folder / Start Menu / app menu. Upgrading is the same command again with the app and backend closed. Your `~/.slopon` (config, database, attachments) stays put. ARM machines aren't supported yet, the installer tells you so instead of half-installing.

### Manual setup

If you like knowing where every file came from, or the one-liner doesn't cover your machine:

1. Get the archive for your platform from the [releases page](https://github.com/DigiDecode/SlopOn.dev/releases): `slopon-windows-x64.zip`, `slopon-linux-x64.tar.gz`, or `slopon-macos-arm64.zip` / `slopon-macos-x64.zip` (arm64 for Apple Silicon, x64 for Intel).
2. Extract it. Three folders come out: `frontend/` (the desktop app), `backend/` (the Node.js server), `launcher/` (the one-command start helper).
3. Install the backend dependencies from the shipped lockfile:

   ```sh
   cd backend
   npm ci
   ```

   Needs Node.js 20 or 22 (later majors aren't verified yet) and git on your PATH. On Linux, `chmod +x frontend/slopon_dev` if the binary lost its exec bit somewhere along the way.

4. Start it with the launcher: `./launcher/slopon.sh` on macOS/Linux, `launcher\slopon.cmd` on Windows. It boots the backend, waits until it's actually listening, then opens the app. Running it twice doesn't spawn a second backend. `--stop` brings the backend down again.

## First run

The backend wakes up, makes itself a home under `~/.slopon` (config, SQLite database, attachments), prints a freshly generated API key in a banner, and starts listening. The app reads the same `~/.slopon/config.json`, so if you came in through the launcher the two find each other and you never type the key. Start the frontend by hand and the app asks for it once.

Logs live under `~/.slopon/logs/`. The classic `node index.js` path and the unsigned-build warnings (right-click then Open on macOS, More info then Run anyway on Windows) are in [`docs/release-README.md`](docs/release-README.md).

## The money part

Free for individuals, and for orgs making less than USD 100,000 aggregate gross revenue (trailing 12 months). Above that, get a commercial license. Whatever the bots generate from your inputs is yours. Plain-language summary in [LICENSING.md](license/LICENSING.md), full terms in [LICENSE.md](license/LICENSE.md).

## Helping out

The `setup.sh` / `setup.bat` scripts in this repo clone and sync the project's dev repositories. See [`docs/workspace-setup.md`](docs/workspace-setup.md) if you want in.
