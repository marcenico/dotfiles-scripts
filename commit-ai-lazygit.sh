#!/usr/bin/env bash
#
# commit-ai-lazygit.sh
#
# Generates commit message CANDIDATES (subject + optional body) with
# Claude Code from the staged diff, and prints one line per candidate
# to stdout in the form:
#
#   <index>|<subject>|<path to a temp file with the full message>
#
# This is meant to be called by lazygit's `menuFromCommand` prompt: each
# stdout line becomes a menu entry (subject shown as the label), and the
# path becomes the value passed to `git commit -F <path>`, which lets the
# final commit include a full multi-line body — something a plain
# `git commit -m "<line>"` can't do.
#
# Unlike commit-ai.sh, this script does NOT stage files, does NOT commit,
# and does NOT ask for confirmation.
#
# Any informational/error text goes to stderr, so stdout only ever
# contains the clean "<index>|<subject>|<path>" lines.
#
# REQUIREMENTS:
#   - Claude Code CLI installed (claude --version) and authenticated
#     (claude /login, or ANTHROPIC_API_KEY / claude setup-token for headless use)
#   - perl (used for reliable multi-line parsing of Claude's response)
#
# USAGE (standalone, for testing):
#   ./commit-ai-lazygit.sh
#   ./commit-ai-lazygit.sh --language es --count 5
#
# USAGE (from lazygit's config.yml, see menuFromCommand prompt in the
# accompanying config snippet):
#   command: 'bash /home/marce/dotfiles-scripts/commit-ai-lazygit.sh'
#
set -euo pipefail

MAX_DIFF_CHARS=10000
MODEL="sonnet"
LANGUAGE="en"
COUNT=3

# --- 0. Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-diff-chars) MAX_DIFF_CHARS="$2"; shift 2 ;;
    --model)          MODEL="$2"; shift 2 ;;
    --language)       LANGUAGE="$2"; shift 2 ;;
    --count)          COUNT="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
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

if ! command -v perl >/dev/null 2>&1; then
  echo "perl was not found in the PATH (required to parse Claude's response)." >&2
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

if (( ${#diff} > MAX_DIFF_CHARS )); then
  diff="${diff:0:$MAX_DIFF_CHARS}

[... diff truncated ...]"
fi

# --- 3. Build the prompt ---
if [[ "$LANGUAGE" == "es" ]]; then
  prompt=$(cat <<EOF
Sos un asistente que redacta mensajes de commit siguiendo la convención Conventional Commits (feat, fix, refactor, chore, docs, style, test, perf).

Basándote en el siguiente diff staged, generá exactamente ${COUNT} alternativas de mensaje de commit en español.

Para cada alternativa:
- Asunto: tipo + alcance opcional + descripción corta (máx. ~72 caracteres), ej: "feat(auth): agregar login con Google".
- Cuerpo: opcional, solo si el cambio lo amerita. Cada línea máx. 100 caracteres. Preferí bullets cortos. Si el cambio es simple, dejalo vacío.

IMPORTANTE: Respondé EXCLUSIVAMENTE repitiendo este bloque ${COUNT} veces (uno por alternativa), sin texto ni explicaciones fuera de los bloques:

===CANDIDATE===
<linea de asunto aca>
---BODY---
<cuerpo aca, o dejalo vacio si no aplica>
===END===

Diff:
$diff
EOF
)
else
  prompt=$(cat <<EOF
You are an assistant that writes commit messages following the Conventional Commits convention (feat, fix, refactor, chore, docs, style, test, perf).

Based on the following staged diff, generate exactly ${COUNT} alternative commit messages in English.

For each alternative:
- Subject: type + optional scope + short description (max ~72 characters), e.g.: "feat(auth): add Google login".
- Body: optional, only if the change warrants it. Each line max 100 characters. Prefer short bullet points. Leave empty if the change is simple.

IMPORTANT: Respond EXCLUSIVELY by repeating this block ${COUNT} times (one per alternative), with no text or explanations outside the blocks:

===CANDIDATE===
<subject line here>
---BODY---
<body here, or leave empty if not applicable>
===END===

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

# --- 5. Parse candidates and write each full message (subject + body) to its own temp file ---
# Records are separated with \x02, fields within a record with \x01, to
# avoid clashing with any character Claude might put in the subject/body.
TMP_DIR="${TMPDIR:-/tmp}/commit-ai-lazygit"
mkdir -p "$TMP_DIR"
rm -f "$TMP_DIR"/msg-*.txt

parsed=$(printf '%s' "$raw_output" | perl -0777 -ne '
  my $i = 0;
  while (/===CANDIDATE===\s*(.*?)\s*---BODY---\s*(.*?)\s*===END===/gs) {
    $i++;
    my ($subj, $body) = ($1, $2);
    $subj =~ s/[\r\n]+/ /g;
    $subj =~ s/\x01|\x02//g;
    $body =~ s/\x01|\x02//g;
    print "$i\x01$subj\x01$body\x02";
  }
')

if [[ -z "$parsed" ]]; then
  echo "Could not parse Claude's response. Raw output:" >&2
  echo "$raw_output" >&2
  exit 1
fi

while IFS=$'\x01' read -r -d $'\x02' idx subj body; do
  [[ -z "$subj" ]] && continue
  msg_file="$TMP_DIR/msg-$idx.txt"
  if [[ -n "${body//[$'\n\t ']/}" ]]; then
    printf '%s\n\n%s\n' "$subj" "$body" > "$msg_file"
  else
    printf '%s\n' "$subj" > "$msg_file"
  fi
  safe_subject=${subj//|/-}
  printf '%s|%s|%s\n' "$idx" "$safe_subject" "$msg_file"
done <<< "$parsed"