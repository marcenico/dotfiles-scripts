#!/usr/bin/env bash
#
# commit-ai.sh
#
# Stages changes and creates a commit with an AI-generated message
# (using Claude Code) based on the diff.
#
# 1. Runs `git add` on the changes (everything by default, or only what's specified).
# 2. Asks Claude to generate a commit message in conventional commits format,
#    based on the staged diff.
# 3. Runs `git commit` with that message.
#
# REQUIREMENTS:
#   - Claude Code CLI installed (claude --version) and authenticated
#     (claude /login, or ANTHROPIC_API_KEY / claude setup-token for headless use)
#
# USAGE:
#   ./commit-ai.sh
#   ./commit-ai.sh --files "src/*" --no-stage
#   ./commit-ai.sh --model sonnet --max-diff-chars 8000
#   ./commit-ai.sh --lang es
#
set -euo pipefail

FILES="."
NO_STAGE=false
MAX_DIFF_CHARS=10000
MODEL="sonnet"
LANGUAGE="en"

# --- 0. Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)           FILES="$2"; shift 2 ;;
    --no-stage)         NO_STAGE=true; shift ;;
    --max-diff-chars)   MAX_DIFF_CHARS="$2"; shift 2 ;;
    --model)            MODEL="$2"; shift 2 ;;
    --lang)         LANGUAGE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$LANGUAGE" != "en" && "$LANGUAGE" != "es" ]]; then
  echo "Invalid --lang value: $LANGUAGE (expected 'en' or 'es')" >&2
  exit 1
fi

# --- Localized strings ---
if [[ "$LANGUAGE" == "es" ]]; then
  MSG_NO_CLAUDE="No se encontró Claude Code en el PATH. Instalalo con:"
  MSG_NO_CLAUDE_HINT="  irm 'https://claude.ai/install.ps1' | iex   (o: npm install -g @anthropic-ai/claude-code)"
  MSG_NO_CHANGES="No hay cambios staged (fuera de lockfiles). Nada para commitear."
  MSG_GENERATING="Generando mensaje de commit con Claude..."
  MSG_CLAUDE_ERROR="Error ejecutando claude:"
  MSG_PARSE_ERROR="No se pudo parsear la respuesta de Claude. Salida cruda:"
  MSG_GENERATED="Mensaje generado:"
  MSG_CONFIRM="¿Commitear con este mensaje? (s/n/e para editar) "
  MSG_NEW_SUBJECT="Nueva línea de asunto: "
  MSG_BODY_PROMPT="Escribí el cuerpo (Enter en blanco para terminar):"
  MSG_CANCELLED="Cancelado. No se hizo el commit (los cambios siguen staged)."
  CONFIRM_YES="s"
  CONFIRM_EDIT="e"
else
  MSG_NO_CLAUDE="Claude Code was not found in the PATH. Install it with:"
  MSG_NO_CLAUDE_HINT="  irm 'https://claude.ai/install.ps1' | iex   (or: npm install -g @anthropic-ai/claude-code)"
  MSG_NO_CHANGES="No changes staged (excluding lockfiles). Nothing to commit."
  MSG_GENERATING="Generating commit message with Claude..."
  MSG_CLAUDE_ERROR="Error running claude:"
  MSG_PARSE_ERROR="Could not parse Claude's response. Raw output:"
  MSG_GENERATED="Generated message:"
  MSG_CONFIRM="Commit with this message? (y/n/e to edit) "
  MSG_NEW_SUBJECT="New subject line: "
  MSG_BODY_PROMPT="Type the body (blank Enter to finish):"
  MSG_CANCELLED="Cancelled. No commit was made (changes are still staged)."
  CONFIRM_YES="y"
  CONFIRM_EDIT="e"
fi

# --- 1. Validation ---
if ! command -v claude >/dev/null 2>&1; then
  echo "$MSG_NO_CLAUDE" >&2
  echo "$MSG_NO_CLAUDE_HINT" >&2
  exit 1
fi

# --- 2. Stage changes ---
if [[ "$NO_STAGE" == false ]]; then
  git add $FILES
fi

# Exclude lockfiles from the diff: they don't add anything to the commit
# message and are usually the reason the diff is huge and slow to compute.
DIFF_PATHSPEC=(
  "."
  ":!pnpm-lock.yaml"
  ":!package-lock.json"
  ":!yarn.lock"
)

diff=$(git diff --cached -- "${DIFF_PATHSPEC[@]}")
if [[ -z "${diff// /}" ]]; then
  echo -e "\033[33m${MSG_NO_CHANGES}\033[0m"
  exit 0
fi

# Truncate if too long (same criterion as the PowerShell version: margin
# under the command line limit; not as critical here since we don't pass
# the diff as a positional argument, but we keep the limit to avoid
# sending a huge prompt)
if (( ${#diff} > MAX_DIFF_CHARS )); then
  diff="${diff:0:$MAX_DIFF_CHARS}

[... diff truncated ...]"
fi

# --- 3. Build the prompt ---
if [[ "$LANGUAGE" == "es" ]]; then
  prompt=$(cat <<EOF
Sos un asistente que redacta mensajes de commit siguiendo la convención Conventional Commits (feat, fix, refactor, chore, docs, style, test, perf).

Basándote en el siguiente diff staged, generá un mensaje de commit en español:
- Primera línea: tipo + alcance opcional + descripción corta (máx. ~72 caracteres), ej: "feat(auth): agregar login con Google"
- Si el cambio lo amerita, agregá un cuerpo breve.
- Cada línea del cuerpo debe tener como máximo 100 caracteres.
- Si necesitás escribir más, dividí el texto en varias líneas.
- Preferí bullets cortos.
- Si el cambio es simple, omití el cuerpo.

IMPORTANTE: Respondé EXCLUSIVAMENTE con este formato, sin explicaciones adicionales:

===SUBJECT===
<linea de asunto aca>
===BODY===
<cuerpo aca, o dejalo vacio si no aplica>
===END===

Diff:
$diff
EOF
)
else
  prompt=$(cat <<EOF
You are an assistant that writes commit messages following the Conventional Commits convention (feat, fix, refactor, chore, docs, style, test, perf).

Based on the following staged diff, generate a commit message in English:
- First line: type + optional scope + short description (max ~72 characters), e.g.: "feat(auth): add Google login"
- If the change warrants it, add a brief body.
- Each line of the body should be at most 100 characters.
- If you need to write more, split the text across several lines.
- Prefer short bullet points.
- If the change is simple, omit the body.

IMPORTANT: Respond EXCLUSIVELY with this format, with no additional explanations:

===SUBJECT===
<subject line here>
===BODY===
<body here, or leave empty if not applicable>
===END===

Diff:
$diff
EOF
)
fi

# --- 4. Call Claude ---
echo -e "\033[36m${MSG_GENERATING}\033[0m"

if ! raw_output=$(claude -p "$prompt" --output-format text --model "$MODEL" --max-turns 1 --allowedTools "" 2>&1); then
  echo "$MSG_CLAUDE_ERROR" >&2
  echo "$raw_output" >&2
  exit 1
fi

# --- 5. Parse the response ---
if [[ ! "$raw_output" =~ ===SUBJECT===[[:space:]]*(.*)[[:space:]]*===BODY===[[:space:]]*(.*)[[:space:]]*===END=== ]]; then
  echo "$MSG_PARSE_ERROR" >&2
  echo "$raw_output" >&2
  exit 1
fi

# bash multiline regex: use perl for a more reliable match than bash's [[ =~ ]]
subject=$(printf '%s' "$raw_output" | perl -0777 -ne 'print $1 if /===SUBJECT===\s*(.*?)\s*===BODY===/s')
body=$(printf '%s' "$raw_output" | perl -0777 -ne 'print $1 if /===BODY===\s*(.*?)\s*===END===/s')

echo -e "\n\033[32m${MSG_GENERATED}\033[0m"
echo -e "\033[32m$subject\033[0m"
if [[ -n "$body" ]]; then
  echo -e "\n\033[32m$body\033[0m"
fi

# --- 6. Confirmation ---
echo ""
read -rp "$MSG_CONFIRM" confirm

if [[ "$confirm" == "$CONFIRM_EDIT" ]]; then
  read -rp "$MSG_NEW_SUBJECT" subject
  echo "$MSG_BODY_PROMPT"
  body_lines=()
  while true; do
    read -r line
    [[ -z "$line" ]] && break
    body_lines+=("$line")
  done
  body=$(printf '%s\n' "${body_lines[@]}")
elif [[ "$confirm" != "$CONFIRM_YES" ]]; then
  echo -e "\033[33m${MSG_CANCELLED}\033[0m"
  exit 0
fi

# --- 7. Commit ---
if [[ -n "$body" ]]; then
  git commit -m "$subject" -m "$body"
else
  git commit -m "$subject"
fi