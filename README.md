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

## commit-ai-lazygit

**`commit-ai-lazygit.sh`** integrates the same AI commit message generation
into [lazygit](https://github.com/jesseduffield/lazygit) as a custom command.

Unlike `commit-ai.sh`, this script does not stage files, does not commit, and
does not ask for confirmation — it only generates message **candidates** from
the already-staged diff and prints them to stdout so lazygit can show them as
a selectable menu.

For each candidate it writes the full commit message (subject + optional
body) to a temp file and prints a line in the form:

```
<index>|<subject>|<path to temp file>
```

This is meant to be used from lazygit's `menuFromCommand` prompt: each line
becomes a menu entry (subject as the label), and the chosen path is passed to
`git commit -F <path>`, so the final commit can include a full multi-line
body — something a plain `git commit -m "<line>"` can't do.

### Usage (standalone, for testing)

```bash
./commit-ai-lazygit.sh
./commit-ai-lazygit.sh --language es --count 5
```

**Flags:**

| Flag                 | Default   | Description                                                |
|----------------------|-----------|-------------------------------------------------------------|
| `--max-diff-chars`   | `10000`   | Truncates the diff sent to Claude to N characters.           |
| `--model`            | `sonnet`  | Claude model to use.                                          |
| `--language`         | `en`      | Language for the generated messages: `en` or `es`.           |
| `--count`            | `3`       | Number of commit message candidates to generate.             |

### lazygit configuration

Add a `customCommands` entry to lazygit's `config.yml` to bind this script to
a key (e.g. `<c-a>`) in the files panel:

```yaml
customCommands:
  - key: "<c-a>"
    description: "AI commit (Claude)"
    context: "files"
    command: 'git commit -F "{{ .Form.Msg }}"'
    loadingText: "Generating commit message with Claude..."
    prompts:
      - type: "menuFromCommand"
        title: "Choose a commit message"
        key: "Msg"
        command: "bash /home/marce/dotfiles-scripts/commit-ai-lazygit.sh"
        filter: '(?P<idx>[0-9]+)\|(?P<subject>[^|]*)\|(?P<path>.*)'
        valueFormat: "{{ .path }}"
        labelFormat: "{{ .idx }}. {{ .subject | yellow }}"
```

With this, stage the files you want (space bar), press `<c-a>`, pick one of
the generated candidates from the menu, and lazygit will commit using that
message's full subject + body via `git commit -F`.
