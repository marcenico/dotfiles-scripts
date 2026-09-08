<#
.SYNOPSIS
    Stages changes and creates a commit with an AI-generated message
    (using Claude Code) based on the diff.

.DESCRIPTION
    1. Runs `git add` on the changes (everything by default, or only what's specified).
    2. Asks Claude to generate a commit message in conventional commits format,
       based on the staged diff.
    3. Runs `git commit` with that message.

.REQUIREMENTS
    - Claude Code CLI installed (claude --version) and authenticated
      (claude /login, or ANTHROPIC_API_KEY / claude setup-token for headless use)

.PARAMETER Language
    Language for the generated commit message and console prompts.
    Accepts "en" (English) or "es" (Spanish). Default: "en".

.EXAMPLE
    .\commit-ai.ps1
    .\commit-ai.ps1 -Files "src/*" -NoStage
    .\commit-ai.ps1 -Language es
#>

param(
    [string]$Files = ".",
    [switch]$NoStage,
    # < ~25KB to avoid exceeding Windows command line limit (~32KB)
    [int]$MaxDiffChars = 10000,
    [string]$Model = "sonnet",
    [ValidateSet("en", "es")]
    [string]$Language = "en"
)

$ErrorActionPreference = "Stop"

# --- Localized strings ---
$Strings = @{
    en = @{
        NoClaudeFound        = "Claude Code was not found in the PATH. Install it with:`n  irm 'https://claude.ai/install.ps1' | iex"
        NoChangesStaged      = "No changes staged. Nothing to commit."
        GeneratingMessage    = "Generating commit message with Claude..."
        ClaudeExecError      = "Error running claude: {0}"
        ParseError           = "Could not parse Claude's response. Raw output:`n{0}"
        GeneratedMessage     = "`nGenerated message:"
        ConfirmPrompt        = "Commit with this message? (y/n/e to edit)"
        NewSubjectPrompt     = "New subject line"
        BodyPrompt           = "Type the body (blank Enter to finish):"
        Cancelled            = "Cancelled. No commit was made (changes are still staged)."
        ConfirmYes           = "y"
        ConfirmEdit          = "e"
    }
    es = @{
        NoClaudeFound        = "No se encontró Claude Code en el PATH. Instalalo con:`n  irm 'https://claude.ai/install.ps1' | iex"
        NoChangesStaged      = "No hay cambios staged. Nada para commitear."
        GeneratingMessage    = "Generando mensaje de commit con Claude..."
        ClaudeExecError      = "Error ejecutando claude: {0}"
        ParseError           = "No se pudo parsear la respuesta de Claude. Salida cruda:`n{0}"
        GeneratedMessage     = "`nMensaje generado:"
        ConfirmPrompt        = "¿Commitear con este mensaje? (s/n/e para editar)"
        NewSubjectPrompt     = "Nueva línea de asunto"
        BodyPrompt           = "Escribí el cuerpo (Enter en blanco para terminar):"
        Cancelled            = "Cancelado. No se hizo el commit (los cambios siguen staged)."
        ConfirmYes           = "s"
        ConfirmEdit          = "e"
    }
}
$T = $Strings[$Language]

function Get-ClaudeExe {
    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-ClaudePrint {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Model = "sonnet"
    )

    $claudeExe = Get-ClaudeExe
    if (-not $claudeExe) {
        throw $T.NoClaudeFound
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $claudeExe
    $psi.ArgumentList.Add("-p")
    $psi.ArgumentList.Add($Prompt)
    $psi.ArgumentList.Add("--output-format")
    $psi.ArgumentList.Add("text")
    $psi.ArgumentList.Add("--model")
    $psi.ArgumentList.Add($Model)
    $psi.ArgumentList.Add("--max-turns")
    $psi.ArgumentList.Add("1")
    $psi.ArgumentList.Add("--allowedTools")
    $psi.ArgumentList.Add("")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0) {
        throw "claude exit $($proc.ExitCode): $stderr$stdout"
    }

    if ($stdout) { return $stdout }
    return $stderr
}

# --- 0. Validation ---
if (-not (Get-ClaudeExe)) {
    Write-Error $T.NoClaudeFound
    exit 1
}

# --- 1. Stage changes ---
if (-not $NoStage) {
    git add $Files
}

# Out-String: git can return string[]; .Length would be lines, not chars
$diff = git diff --cached | Out-String
if (-not $diff.Trim()) {
    Write-Host $T.NoChangesStaged -ForegroundColor Yellow
    exit 0
}

# CreateProcess on Windows ~32KB command line; leave margin
if ($diff.Length -gt $MaxDiffChars) {
    $diff = $diff.Substring(0, $MaxDiffChars) + "`n`n[... diff truncated ...]"
}

# --- 2. Build the prompt ---
if ($Language -eq "es") {
    $prompt = @"
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
"@
} else {
    $prompt = @"
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
"@
}

# --- 3. Call Claude ---
Write-Host $T.GeneratingMessage -ForegroundColor Cyan

try {
    $rawOutput = Invoke-ClaudePrint -Prompt $prompt -Model $Model
} catch {
    Write-Error ($T.ClaudeExecError -f $_)
    exit 1
}

# --- 4. Parse the response ---
if ($rawOutput -notmatch "(?s)===SUBJECT===\s*(.*?)\s*===BODY===\s*(.*?)\s*===END===") {
    Write-Error ($T.ParseError -f $rawOutput)
    exit 1
}

$subject = $Matches[1].Trim()
$body = $Matches[2].Trim()

Write-Host $T.GeneratedMessage -ForegroundColor Green
Write-Host $subject -ForegroundColor Green
if ($body) {
    Write-Host "`n$body" -ForegroundColor Green
}

# --- 5. Confirmation ---
Write-Host ""
$confirm = Read-Host $T.ConfirmPrompt

if ($confirm -eq $T.ConfirmEdit) {
    $subject = Read-Host $T.NewSubjectPrompt
    Write-Host $T.BodyPrompt
    $bodyLines = @()
    while ($true) {
        $line = Read-Host
        if (-not $line) { break }
        $bodyLines += $line
    }
    $body = $bodyLines -join "`n"
} elseif ($confirm -ne $T.ConfirmYes) {
    Write-Host $T.Cancelled -ForegroundColor Yellow
    exit 0
}

# --- 6. Commit ---
if ($body) {
    git commit -m $subject -m $body
} else {
    git commit -m $subject
}
