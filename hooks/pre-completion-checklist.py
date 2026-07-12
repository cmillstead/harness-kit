#!/usr/bin/env python3
"""Claude Code verification hook: gate commits, record verifications.

One script, two Claude Code events (selected via hook_event_name in stdin):

  PreToolUse  (matcher: Bash) — GATE only. Before `git commit`/`git push`,
              deny if this session has not recorded BOTH a test and a lint
              run for this working directory. Also denies a commit whose
              effective target could be a DIFFERENT repo than this event's
              (a chained `cd &&`, or a GLOBAL `-C`/`--git-dir`/`--work-tree`
              option BEFORE the subcommand) before ever consulting recorded
              evidence. Commit detection is a best-effort NUDGE (raw-text regex
              OR a position-aware git-argument parse) and retarget detection a
              position-aware check of git's GLOBAL options — NOT a full shell
              parser; the git-level `hooks/pre-commit-verify.sh` is the
              enforcing boundary. Never records anything.
  PostToolUse (matcher: Bash) — RECORD only. PostToolUse fires ONLY after a
              tool call SUCCEEDS (PostToolUseFailure fires on failure and is
              NOT registered), so the event itself is the success signal — no
              exit-code/tool_response inspection is needed. A command is
              recorded only if it passes ANCHORED validation (below), which
              rejects masked/chained forms like `npm test || true`.

Anchored validation: reject any command containing || ; | & $( ` or a newline;
split the rest on && and require EVERY segment to match an approved verification
command anchored at its start (the approved-command allowlist requires the
matched name be followed by whitespace or end-of-segment, so `make test-noop`
is rejected — it must not be accepted as `make test`). There is deliberately
no leading-`cd` allowance: `cd other-repo && npm test` would run tests
elsewhere yet authorize this repo.

Malformed events: the envelope (event is a dict; tool_input is a dict;
tool_input.command is a str) is validated before any dict access, so a
top-level `[]` or a `tool_input: null` can never crash this hook. The
response is asymmetric by role and identifiability:
  - RECORD (PostToolUse) malformed  -> silent (record nothing; a best-effort
    recorder must never fabricate evidence or crash).
  - GATE  identifiable-commit malformed (tool_name == "Bash" but the rest is
    unparseable) -> explicit DENY (fail closed: we cannot rule out a commit).
  - GATE  unidentifiable event (a top-level `[]`, or tool_name != "Bash")
    -> silent ALLOW. It cannot be a commit (the matcher is all-Bash), and
    gating every unrelated tool call on a parse failure would brick the
    session.

State: a per-user 0700 dir under the system temp dir (validated via lstat; if it
is not a private self-owned dir, or cannot be created, the hook FAILS CLOSED).
One 0600 file per (session_id, project_root), where project_root is the git
top-level of the event cwd (CLAUDE_PROJECT_DIR is only a fallback, and only when
cwd is inside it). Only {category, time} is stored — never command text.
"""

import glob
import hashlib
import json
import os
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import time

STALE_SECONDS = 7200          # forget verifications older than 2 hours
RECENT_SECONDS = 1800         # the gate looks back 30 minutes

# Approved verification commands, anchored at a segment start (args allowed).
# Kept in sync with the Stop hook's command set: pytest via `python3 -m pytest`,
# `flake8`, `cargo check`, and the project-local `./node_modules/.bin/tsc`.
# R-fix1 (Codex 9): the trailing anchor is `(?=\s|$)`, NOT `\b`. A bare `\b`
# is satisfied by ANY non-word character following the command name, so
# `make test-noop` (word `test` -> non-word `-`) wrongly matched `make test`,
# letting a no-op target record real test/lint evidence. `(?=\s|$)` requires
# the approved command to be followed by whitespace-then-arguments or by the
# end of the segment, so `make test-noop` no longer matches `make test`
# while `make test -j4` still does. Applies uniformly: every alternative
# shares this single trailing anchor.
APPROVED_RE = re.compile(
    r"^(npm test|npm run test|npm run lint|npx jest|npx vitest|npx eslint|"
    r"pytest|python3 -m pytest|ruff check|flake8|mypy|"
    r"cargo test|cargo clippy|cargo check|go test|"
    r"make test|make lint|make check|shellcheck|"
    r"tsc --noEmit|\./node_modules/\.bin/tsc|bash -n)(?=\s|$)"
)
TEST_RE = re.compile(
    r"\b(npm test|npm run test|npx jest|npx vitest|pytest|cargo test|"
    r"go test|make test|bash -n)\b"
)
LINT_RE = re.compile(
    r"\b(npm run lint|npx eslint|tsc --noEmit|mypy|ruff check|flake8|"
    r"cargo clippy|cargo check|make lint|make check|shellcheck)\b"
)
# --- Commit / repo-retarget detection (best-effort NUDGE) --------------------
# This gate is a best-effort NUDGE, not the enforcing boundary: the git-level
# `hooks/pre-commit-verify.sh` hook is what actually enforces verification at
# commit time. So this detection is deliberately SIMPLE and ROBUST rather than a
# full shell parser — it parses git's own argument STRUCTURE
# (`git [GLOBAL-OPTIONS] <subcommand> [SUBCOMMAND-ARGS]`), not arbitrary shell.
#
# Commit detection is two independent checks (see _analyze_command): a regex over
# the RAW string matching a `git`, then zero-or-more option tokens, then
# `commit`/`push` in subcommand position — catching wrapper prefixes (`env`,
# `command`, `exec`, `bash -c "..."`), comment/newline boundaries, and
# `git -C /path commit`; OR a position-aware git-argument parse (_parse_git) that
# walks past git's GLOBAL options to find the real subcommand, so a quoted
# spaced-path option (`git -C "/other repo" commit`) is still detected while a
# `commit` token that is only a FLAG VALUE (`git log --grep commit`) is NOT.
#
# Retarget detection is position-aware: a retarget flag only counts when it is a
# GLOBAL option BEFORE the subcommand (`git -C <path> commit`), so `commit`'s own
# `-C <commit>` reuse option (`git commit -C HEAD`) is not a false positive; plus
# a `cd` that is a chained COMMAND WORD (first token, or after a shell operator),
# so `cd` inside a quoted message (`git commit -m "release; cd notes"`) or as a
# message value (`git commit -m cd`) is not flagged. Exotic subshell/eval forms
# (e.g. `(cd /other && git commit)`, which tokenizes to `(cd` rather than a bare
# `cd`) may evade this nudge but are still blocked at commit time by the git hook.
_COMMIT_RE = re.compile(
    r"\bgit\b(?:\s+-{1,2}\S+(?:[=\s]\S+)?)*\s+(?:commit|push)\b"
)

PROJECT_MARKERS = [
    "package.json", "tsconfig.json", "deno.json",
    "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
    "Pipfile", "tox.ini", "Cargo.toml", "go.mod",
    "pom.xml", "build.gradle", "build.gradle.kts", "build.sbt",
    "Directory.Build.props", "Gemfile", "Rakefile", "composer.json",
    "Package.swift", "pubspec.yaml", "mix.exs",
    "stack.yaml", "cabal.project",
    "CMakeLists.txt", "meson.build", "configure.ac",
    "build.zig", "deps.edn", "project.clj", "Project.toml",
    "Makefile", "Justfile",
]
GLOB_MARKERS = ["*.csproj", "*.sln", "*.xcodeproj", "*.nimble"]


class StateDirError(Exception):
    """The per-user state dir exists but is not a private, self-owned dir."""


def _dir_is_secure(info) -> bool:
    return (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
        and stat.S_IMODE(info.st_mode) == 0o700
    )


def state_dir() -> str:
    # ONE stable per-user dir so a verification recorded at PostToolUse is still
    # found by the PreToolUse gate. FAIL CLOSED (raise StateDirError) if it is not
    # a real, self-owned, non-symlink 0700 dir — OR if creating it fails (R4-4:
    # os.makedirs/os.chmod OSError must not slip past as an ALLOW at the gate).
    base = os.path.join(tempfile.gettempdir(), f"claude-harness-{os.getuid()}")
    try:
        os.makedirs(base, mode=0o700)   # no exist_ok — we validate the result below
    except FileExistsError:
        pass                            # already present, or lost a create race
    except OSError as exc:
        raise StateDirError(base) from exc
    # R5-3: lstat and confirm a real, self-owned, NON-symlink dir BEFORE any chmod,
    # so a symlink planted in the create window can never have its TARGET chmod'd.
    try:
        info = os.lstat(base)
    except OSError as exc:
        raise StateDirError(base) from exc
    if not (
        stat.S_ISDIR(info.st_mode)
        and not stat.S_ISLNK(info.st_mode)
        and info.st_uid == os.getuid()
    ):
        raise StateDirError(base)       # not our own real dir — refuse WITHOUT touching it
    # Only now, on a validated self-owned real dir, tighten the mode if needed and
    # RE-lstat before the full secure check (owner + non-symlink + exactly 0700).
    if stat.S_IMODE(info.st_mode) != 0o700:
        try:
            os.chmod(base, 0o700)
            info = os.lstat(base)
        except OSError as exc:
            raise StateDirError(base) from exc
    if not _dir_is_secure(info):
        raise StateDirError(base)
    return base


def _git_toplevel(cwd: str):
    # Read-only resolution of the git top-level of the EVENT cwd. Returns a real
    # path or None. This is the repo the command actually ran in.
    try:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode == 0 and result.stdout.strip():
        return os.path.realpath(result.stdout.strip())
    return None


def project_root(cwd: str) -> str:
    # R4-1: resolve the git top-level of the EVENT cwd FIRST — that is the repo
    # the command ran in, and it cannot be spoofed by a stale CLAUDE_PROJECT_DIR
    # left over after Claude cd'd into a different repo in an earlier tool call.
    # Only fall back to CLAUDE_PROJECT_DIR when git resolution fails AND cwd is
    # inside it; otherwise use the cwd itself.
    cwd_real = os.path.realpath(cwd)
    top = _git_toplevel(cwd)
    if top:
        return top
    env_root = os.environ.get("CLAUDE_PROJECT_DIR")
    if env_root:
        env_real = os.path.realpath(env_root)
        if cwd_real == env_real or cwd_real.startswith(env_real + os.sep):
            return env_real
    return cwd_real


def state_file(session_id: str, root: str) -> str:
    key = hashlib.sha256(f"{session_id}\0{root}".encode()).hexdigest()[:16]
    return os.path.join(state_dir(), f"verify-{key}.json")


def _is_number(value) -> bool:
    # bool is a subclass of int; a JSON true/false must not pass as a timestamp.
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def load_state(path: str) -> dict:
    empty = {"verifications": [], "last_updated": time.time()}
    try:
        with open(path) as handle:
            state = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return empty
    if not isinstance(state, dict):
        return empty
    verifications = state.get("verifications")
    last_updated = state.get("last_updated")
    if not isinstance(verifications, list) or not _is_number(last_updated):
        return empty
    for entry in verifications:
        # S3: validate value TYPES, not just key presence — a string `time`
        # would crash the `now - time` arithmetic in the gate.
        if not isinstance(entry, dict):
            return empty
        if not isinstance(entry.get("category"), str) or not _is_number(entry.get("time")):
            return empty
    if time.time() - last_updated > STALE_SECONDS:
        return empty
    return state


def save_state(path: str, state: dict) -> None:
    state["last_updated"] = time.time()
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(state, handle)
    os.replace(tmp, path)


def categories(command: str) -> list:
    found = []
    if TEST_RE.search(command):
        found.append("test")
    if LINT_RE.search(command):
        found.append("lint")
    return found


def has_project(root: str) -> bool:
    if any(os.path.exists(os.path.join(root, marker)) for marker in PROJECT_MARKERS):
        return True
    return any(glob.glob(os.path.join(root, pattern)) for pattern in GLOB_MARKERS)


def should_record(command: str) -> bool:
    # Reject shell metacharacters that could chain or mask a failure. `&&` is
    # the only permitted separator, so strip it before the bare-`&` check.
    if "\n" in command:
        return False
    if any(token in command for token in (";", "|", "$(", "`")):
        return False
    if "&" in command.replace("&&", ""):
        return False
    segments = [segment.strip() for segment in command.split("&&")]
    for segment in segments:
        if not segment:
            return False
        # No inline-`cd` allowance (R3-3): `cd other-repo && npm test` runs tests
        # elsewhere but would authorize THIS repo. A real dir change is a separate
        # tool call, so the next event already carries the correct cwd.
        if not APPROVED_RE.match(segment):
            return False
    return bool(categories(command))


def write_verification(command: str, path: str) -> None:
    state = load_state(path)
    now = time.time()
    for category in categories(command):
        state["verifications"].append({"category": category, "time": now})
    state["verifications"] = state["verifications"][-20:]
    save_state(path, state)


def _is_git(word: str) -> bool:
    # A git invocation's command word is `git` or a path ending in `/git`
    # (e.g. /usr/bin/git).
    return word == "git" or word.endswith("/git")


# Global options that CONSUME the next token as their value when not `=`-glued.
# Erring toward "takes no value" only causes a safe MISS for a nudge (we would
# read a value as the subcommand), never a false positive — so an unknown
# value-taking global is acceptable here.
_VALUE_TAKING_GLOBALS = frozenset({
    "-C", "-c", "--git-dir", "--work-tree",
    "--namespace", "--exec-path", "--config-env",
})

# Shell operators that, when they PRECEDE a `cd` token, mark that `cd` as a
# chained command word (a real directory change) rather than an argument value.
_SHELL_OPERATORS = ("&&", "||", ";", "|", "&")


def _parse_git(tokens: list):
    # Position-aware parse of the FIRST git invocation, respecting git's own
    # structure: `git [GLOBAL-OPTIONS] <subcommand> [SUBCOMMAND-ARGS]`. Returns
    # (found, subcommand_or_None, global_opts). This lets the gate tell a GLOBAL
    # `-C <path>` retarget (BEFORE the subcommand) apart from `commit`'s own
    # `-C <commit>` option (AFTER it), and tell the `commit`/`push` subcommand
    # apart from a `commit` token that is only a flag VALUE (`git log --grep
    # commit`).
    for i, tok in enumerate(tokens):
        if not _is_git(tok):
            continue
        global_opts = []
        j = i + 1
        while j < len(tokens):
            opt = tokens[j]
            if not opt.startswith("-"):
                return True, opt, global_opts  # first non-option token = subcommand
            global_opts.append(opt)
            # A value-taking global WITHOUT an inline `=` consumes the NEXT token.
            if "=" not in opt and opt in _VALUE_TAKING_GLOBALS:
                j += 1
            j += 1
        return True, None, global_opts  # git with only options, no subcommand
    return False, None, []


def _is_retarget_global(opt: str) -> bool:
    # A GLOBAL git option that points the command at a DIFFERENT working tree/repo:
    # `-C`/`-C<glued>`, or `--git-dir`/`--work-tree` (bare or `=`-glued). NOT `-c`
    # (config), which does not retarget.
    if opt == "-C" or (opt.startswith("-C") and len(opt) > 2):
        return True
    if opt in ("--git-dir", "--work-tree"):
        return True
    return opt.startswith("--git-dir=") or opt.startswith("--work-tree=")


def _has_cd_command_word(tokens: list) -> bool:
    # True if a bare `cd` appears as a chained COMMAND WORD: the FIRST token, or a
    # token whose PREVIOUS token is a shell operator. A `cd` that is a message
    # value (`git commit -m cd`, prev token `-m`) or inside a quoted message
    # (`"release; cd notes"`, one token) is NOT a command word — no false positive.
    for i, tok in enumerate(tokens):
        if tok != "cd":
            continue
        if i == 0 or tokens[i - 1] in _SHELL_OPERATORS:
            return True
    return False


def _analyze_command(command: str):
    # Best-effort NUDGE (see the module comment above _COMMIT_RE). Returns
    # (is_commit, is_retargeted).
    #
    # is_commit: a raw-text regex for a `git ... commit|push` form (catches
    # wrapper prefixes, comment/newline boundaries, `git -C /path commit`), OR a
    # position-aware parse whose SUBCOMMAND is `commit`/`push` (catches the quoted
    # spaced-path option case, and rejects a `commit` that is only a flag value).
    #
    # is_retargeted (only when is_commit): a GLOBAL retarget option BEFORE the
    # subcommand (-C / --git-dir / --work-tree), or a chained `cd` command word.
    # On unbalanced quotes we cannot tokenize, so a commit-looking command is
    # conservatively treated as retargeted (deny).
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = None

    if tokens is not None:
        found, subcommand, global_opts = _parse_git(tokens)
    else:
        found, subcommand, global_opts = False, None, []

    is_commit = bool(_COMMIT_RE.search(command)) or (
        found and subcommand in ("commit", "push")
    )

    if tokens is None:
        is_retargeted = is_commit  # unparseable commit-looking command -> deny
    else:
        is_retargeted = is_commit and (
            any(_is_retarget_global(opt) for opt in global_opts)
            or _has_cd_command_word(tokens)
        )
    return is_commit, is_retargeted


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))


def gate(command: str, path: str, root: str) -> None:
    if not has_project(root):
        return  # docs-only repo, nothing to verify
    state = load_state(path)
    now = time.time()
    recent = [v for v in state["verifications"] if now - v.get("time", 0) < RECENT_SECONDS]
    has_test = any(v.get("category") == "test" for v in recent)
    has_lint = any(v.get("category") == "lint" for v in recent)

    missing = []
    if not has_test:
        missing.append("tests (npm test, pytest, cargo test, etc.)")
    if not has_lint:
        missing.append("linting/typecheck (npm run lint, tsc --noEmit, mypy, etc.)")
    if not missing:
        return

    msg = "PRE-COMPLETION CHECKLIST FAILED\n\n"
    msg += "You are about to commit/push but have NOT run:\n"
    for item in missing:
        msg += f"  - {item}\n"
    msg += "\nRun the missing checks first, then retry the commit. "
    msg += "Golden Principle #7: Verify Before Claiming Done.\n"
    msg += "If tests/linting don't apply to this repo, explain why to the user."
    deny(msg)


MALFORMED_DENY_REASON = "malformed hook event — denying commit gate fail-closed"


def _dispatch(event: dict) -> None:
    # R-fix2 (Codex 10): validate the envelope BEFORE any dict access. Roles
    # are asymmetric on a malformed event:
    #   RECORD (PostToolUse)  -> exit silently, record nothing. A best-effort
    #                            recorder must never fabricate evidence or crash.
    #   GATE   (PreToolUse, or the default/missing hook_event_name)
    #          -> if the event is identifiably a commit-gate evaluation
    #             (tool_name == "Bash" at the gate) but malformed, emit an
    #             explicit deny (fail-closed: we cannot rule out that the
    #             unparseable command was a commit). If it is not even
    #             identifiable as a Bash tool call, exit silently — gating
    #             every unrelated tool call on a parse failure would brick
    #             the session, and the gate only owes fail-closed behavior
    #             for commit attempts.
    if event.get("tool_name") != "Bash":
        return

    hook_event = event.get("hook_event_name", "")
    is_gate = hook_event != "PostToolUse"

    tool_input = event.get("tool_input")
    if not isinstance(tool_input, dict):
        if is_gate:
            deny(MALFORMED_DENY_REASON)
        return

    command = tool_input.get("command", "")
    if not isinstance(command, str):
        if is_gate:
            deny(MALFORMED_DENY_REASON)
        return
    if not command:
        return

    session_id = event.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        session_id = "default"
    cwd = event.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        cwd = os.getcwd()

    try:
        root = project_root(cwd)

        if not is_gate:  # PostToolUse — record only
            if should_record(command):
                try:
                    write_verification(command, state_file(session_id, root))
                except (StateDirError, OSError):
                    pass  # cannot record safely; the gate will fail closed
            return

        # Shell-aware (shlex) trigger: is this a git commit/push, and does its
        # effective target look like a DIFFERENT repo than this event's? See
        # `_analyze_command` for the two defects the old regexes had.
        is_commit, is_retargeted = _analyze_command(command)
        if not is_commit:
            return  # PreToolUse (default) — gate only fires on commit/push

        # Evidence is bound to THIS event's repo root; deny a commit whose
        # effective target could be a different repo, before ever consulting
        # recorded evidence.
        if is_retargeted:
            deny(
                "run git commit as a standalone command from the repo root "
                "(no cd/-C/--git-dir)"
            )
            return

        # R4-4: catch BOTH the security refusal and any I/O error, and emit a
        # deny DECISION (not a bare exit 1 — a PreToolUse exit 1 does NOT block).
        try:
            path = state_file(session_id, root)
        except (StateDirError, OSError) as exc:
            if has_project(root):   # only block a real project, not docs-only
                deny(
                    "PRE-COMPLETION CHECKLIST: cannot verify.\n"
                    f"The harness state directory is unusable (insecure or unwritable): {exc}\n"
                    "Refusing to certify verification (fail-closed). Fix that "
                    "directory's ownership/permissions, then retry."
                )
            return
        gate(command, path, root)
    except Exception:
        # R-fix2: nothing in either path may raise an uncaught exception on
        # any input. An unexpected failure below the envelope checks above
        # still fails closed on the GATE path and silently on RECORD.
        if is_gate:
            deny(MALFORMED_DENY_REASON)


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    if not isinstance(event, dict):
        return  # not identifiable as anything (e.g. a top-level `[]`) -> no-op
    try:
        _dispatch(event)
    except Exception:
        pass  # last-resort safety net; _dispatch already fails closed on GATE


if __name__ == "__main__":
    main()
