# scripts

A collection of personal utility scripts. Currently includes tools to
generate AI-powered commit messages using [Claude Code](https://claude.ai/code).

## commit-ai

Automates the `git add` + `git commit` flow, generating the commit message
with Claude from the staged diff, following the
[Conventional Commits](https://www.conventionalcommits.org/) convention
(`feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `perf`).

Includes two equivalent versions:

- **`commit-ai.ps1`** — PowerShell (Windows).
- **`commit-ai.sh`** — Bash (Linux/macOS/WSL/Git Bash).

### Flow

1. Runs `git add` on the changes (everything by default, or only what's
   specified).
2. Sends the staged diff to Claude (`claude -p ...`) asking for a commit
   message in a delimited format (`===SUBJECT===` / `===BODY===` / `===END===`).
3. Shows the generated message and asks for confirmation before committing
   (accept, cancel, or manually edit).
4. Runs `git commit` with the resulting message.

### Requirements

- [Claude Code CLI](https://claude.ai/code) installed and authenticated:
  - `claude /login`, or
  - `ANTHROPIC_API_KEY` / `claude setup-token` for headless use.

### Usage — PowerShell

```powershell
.\commit-ai.ps1
.\commit-ai.ps1 -Files "src/*" -NoStage
.\commit-ai.ps1 -Language es
```

**Parameters:**

| Parameter         | Default   | Description                                                |
|-------------------|-----------|-------------------------------------------------------------|
| `-Files`          | `.`       | Path(s) to stage with `git add`.                             |
| `-NoStage`        | (off)     | Skips `git add`; uses whatever is already staged.            |
| `-MaxDiffChars`   | `10000`   | Truncates the diff sent to Claude to N characters.           |
| `-Model`          | `sonnet`  | Claude model to use.                                          |
| `-Language`       | `en`      | Language for the message and prompts: `en` or `es`.          |

### Usage — Bash

```bash
./commit-ai.sh
./commit-ai.sh --files "src/*" --no-stage
./commit-ai.sh --model sonnet --max-diff-chars 8000
./commit-ai.sh --lang es
```

**Flags:**

| Flag                 | Default   | Description                                                |
|----------------------|-----------|-------------------------------------------------------------|
| `--files`            | `.`       | Path(s) to stage with `git add`.                             |
| `--no-stage`         | (off)     | Skips `git add`; uses whatever is already staged.            |
| `--max-diff-chars`   | `10000`   | Truncates the diff sent to Claude to N characters.           |
| `--model`            | `sonnet`  | Claude model to use.                                          |
| `--lang`             | `en`      | Language for the message and prompts: `en` or `es`.          |

The Bash version also excludes lockfiles (`pnpm-lock.yaml`, `package-lock.json`,
`yarn.lock`) from the diff sent to Claude, to avoid huge diffs that don't add
useful context to the commit message.

### Optional: `gcommit` shortcut

To call the script from anywhere as `gcommit`, add a wrapper function to your
shell profile.

**PowerShell** — add to your `$PROFILE`:

```powershell
function gcommit {
    & "$env:USERPROFILE\scripts\commit-ai.ps1" @args
}
```

**Bash** — add to your `~/.bashrc` (or `~/.bash_profile`):

```bash
gcommit() {
  bash "$HOME/scripts/commit-ai.sh" "$@"
}
```

### Notes

- If there are no staged changes, the script does nothing.
- If the diff exceeds `MaxDiffChars` / `--max-diff-chars`, it gets truncated
  before being sent to Claude (to avoid exceeding Windows command line limits).
- When confirming with `e`/`edit`, you can manually rewrite the subject and
  body of the commit before applying it.
