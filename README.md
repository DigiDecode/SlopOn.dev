# SlopOn.dev

This is a **meta-repository** for the SlopOn project. It does not contain application code — instead it ships bootstrap scripts (`setup.sh` for macOS/Linux, `setup.bat` for Windows) that clone and keep in sync all of the project's repositories as sibling folders inside this directory. Run one script on a fresh machine and you get the entire workspace.

After a successful run, the folder layout looks like this:

```
SlopOn.dev/
├── setup.sh          # bootstrap for macOS / Linux
├── setup.bat         # bootstrap for Windows
├── frontend/         # cloned from DigiDecode/slopon_frontend
├── backend/          # cloned from DigiDecode/slopon_backend
├── gpt_markdown/     # cloned from DigiDecode/gpt_markdown
├── re-editor/        # cloned from DigiDecode/re-editor
└── re-highlight/     # cloned from DigiDecode/re-highlight
```

## Prerequisites

- **git 2.7 or newer** installed and available on your `PATH`. Verify with `git --version`.
- **For the default SSH mode:** a GitHub SSH key configured on your account. See GitHub's guide [Generating a new SSH key and adding it to the ssh-agent](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).
- **For `--https` mode:** the project repositories are **private**, so HTTPS clones require authentication. Configure a GitHub [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) and/or a [git credential helper](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git) — git will prompt for credentials as needed.

## Quick start

### Windows

```bat
git clone git@github.com:DigiDecode/SlopOn.dev.git
cd SlopOn.dev
setup.bat
```

To clone over HTTPS instead of SSH:

```bat
setup.bat --https
```

### macOS / Linux

```bash
git clone git@github.com:DigiDecode/SlopOn.dev.git
cd SlopOn.dev
./setup.sh
```

If `./setup.sh` does not run (e.g. the executable bit was lost), fall back to:

```bash
bash setup.sh
```

To clone over HTTPS instead of SSH:

```bash
./setup.sh --https
```

## What the script does

- Verifies that `git` is installed and on your `PATH` before doing anything else.
- **Clones** any project repository whose folder is missing.
- **Pulls** updates (`git pull`) for any repository that is already present.
- **Warns and skips** a folder that exists but is not a git checkout — it is never modified or deleted.
- Never deletes, force-resets, or otherwise destroys any local work; git itself protects uncommitted changes during a pull.
- Prints per-repository progress and a final summary, and exits with code `0` only when every repository was successfully cloned or pulled (any failure, including a non-git folder, yields a non-zero exit).

## Updating later

Re-run the same script at any time to pull the latest changes across all repositories:

```bash
./setup.sh        # macOS / Linux
```

```bat
setup.bat         # Windows
```

Repositories that are missing are cloned; repositories that are present are pulled.

## Troubleshooting

- **`Permission denied (publickey)`** — your SSH key is not set up (or not added to your GitHub account). Either [configure an SSH key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh) or re-run with `--https`. Because the repositories are private, HTTPS still requires a personal access token / credential helper.
- **HTTPS authentication failure** — set up a GitHub [personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) and a [credential helper](https://docs.github.com/en/get-started/getting-started-with-git/caching-your-github-credentials-in-git), then re-run with `--https`.
- **Pull fails with uncommitted changes / diverged branches** — the script reports the repository as failed and leaves it untouched. Commit or stash your changes, then re-run the script.
- **`WARNING ... is not a git repository`** — a folder with a repository's name exists but is not a git checkout. Remove or rename that folder manually, then re-run the script.
