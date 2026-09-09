#!/usr/bin/env bash
#
# commit-ai-lazygit.sh
#
# Generates commit message CANDIDATES with Claude Code from the staged
# diff and prints them, one per line, to stdout.
#
# Unlike commit-ai.sh, this script does NOT stage files, does NOT commit,
# and does NOT ask for confirmation — it's meant to be called by lazygit's
# `menuFromCommand` prompt, which treats each line of stdout as a
# selectable menu entry. Lazygit itself runs `git commit -m "<selected>"`
# with whichever line the user picks.
#
# Any informational/error text goes to stderr, so stdout only ever
# contains clean candidate lines.
#
# REQUIREMENTS:
#   - Claude Code CLI installed (claude --version) and authenticated
#     (claude /login, or ANTHROPIC_API_KEY / claude setup-token for headless use)
#
# USAGE (standalone, for testing):
#   ./commit-ai-lazygit.sh
#   ./commit-ai-lazygit.sh --language es --count 5
#
# USAGE (from lazygit's config.yml, see menuFromCommand prompt):
#   command: 'bash "$HOME/scripts/commit-ai-lazygit.sh"'
#
set -euo pipefail

MAX_DIFF_CHARS=10000
MODEL="sonnet"
LANGUAGE="en"
COUNT=3

# --- 0. Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
  --max-diff-chars)
    MAX_DIFF_CHARS="$2"
    shift 2
    ;;
  --model)
    MODEL="$2"
    shift 2
    ;;
  --language)
    LANGUAGE="$2"
    shift 2
    ;;
  --count)
    COUNT="$2"
    shift 2
    ;;
  *)
    echo "Unknown argument: $1" >&2
    exit 1
    ;;
  esac
done

if [[ "$LANGUAGE" != "en" && "$LANGUAGE" != "es" ]]; then
  echo "Invalid --language value: $LANGUAGE (expected 'en' or 'es')" >&2
  exit 1
fi

# --- 1. Validation ---
if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code was not found in the PATH." >&2
  exit 1
fi

# --- 2. Read the staged diff (files must already be staged, e.g. via lazygit's space key) ---
DIFF_PATHSPEC=(
  "."
  ":!pnpm-lock.yaml"
  ":!package-lock.json"
  ":!yarn.lock"
)

diff=$(git diff --cached -- "${DIFF_PATHSPEC[@]}")
if [[ -z "${diff// /}" ]]; then
  echo "No staged changes (excluding lockfiles). Stage something first." >&2
  exit 1
fi

if ((${#diff} > MAX_DIFF_CHARS)); then
  diff="${diff:0:$MAX_DIFF_CHARS}

[... diff truncated ...]"
fi

# --- 3. Build the prompt ---
if [[ "$LANGUAGE" == "es" ]]; then
  prompt=$(
    cat <<EOF
Sos un asistente que redacta mensajes de commit siguiendo la convención Conventional Commits (feat, fix, refactor, chore, docs, style, test, perf).

Basándote en el siguiente diff staged, generá exactamente ${COUNT} alternativas de mensaje de commit en español, cada una de una sola línea (tipo + alcance opcional + descripción corta, máx. ~72 caracteres), ej: "feat(auth): agregar login con Google".

IMPORTANTE:
- Respondé EXCLUSIVAMENTE con ${COUNT} líneas, una alternativa por línea.
- No numeres las líneas, no uses bullets, no uses comillas, no agregues explicaciones ni texto extra.
- No repitas alternativas.

Diff:
$diff
EOF
  )
else
  prompt=$(
    cat <<EOF
You are an assistant that writes commit messages following the Conventional Commits convention (feat, fix, refactor, chore, docs, style, test, perf).

Based on the following staged diff, generate exactly ${COUNT} alternative commit messages in English, each a single line (type + optional scope + short description, max ~72 characters), e.g.: "feat(auth): add Google login".

IMPORTANT:
- Respond EXCLUSIVELY with ${COUNT} lines, one alternative per line.
- Do not number the lines, do not use bullets, do not use quotes, do not add explanations or extra text.
- Do not repeat alternatives.

Diff:
$diff
EOF
  )
fi

# --- 4. Call Claude ---
echo "Generating commit message candidates with Claude..." >&2

if ! raw_output=$(claude -p "$prompt" --output-format text --model "$MODEL" --max-turns 1 --allowedTools "" 2>/tmp/commit-ai-lazygit.err); then
  cat /tmp/commit-ai-lazygit.err >&2
  echo "Error running claude." >&2
  exit 1
fi

# --- 5. Clean up and print candidates (one per line, to stdout only) ---
# Strips leading bullets/numbering/quotes Claude might add despite instructions,
# and drops blank lines.
printf '%s\n' "$raw_output" |
  sed -E 's/^[[:space:]]*[-*][[:space:]]+//; s/^[[:space:]]*[0-9]+[.)][[:space:]]+//; s/^"//; s/"$//' |
  sed -E '/^[[:space:]]*$/d'
