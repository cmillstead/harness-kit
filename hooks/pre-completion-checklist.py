#!/usr/bin/env python3
"""Claude Code verification hook: gate commits, record verifications.

One script, two Claude Code events (selected via hook_event_name in stdin):

  PreToolUse  (matcher: Bash) — GATE only. Before `git commit`/`git push`,
              deny if this session has not recorded BOTH a test and a lint
              run for this working directory. Never records anything.
  PostToolUse (matcher: Bash) — RECORD only. PostToolUse fires ONLY after a
              tool call SUCCEEDS (PostToolUseFailure fires on failure and is
              NOT registered), so the event itself is the success signal — no
              exit-code/tool_response inspection is needed. A command is
              recorded only if it passes ANCHORED validation (below), which
              rejects masked/chained forms like `npm test || true`.

Anchored validation: reject any command containing || ; | & $( ` or a newline;
split the rest on && and require EVERY segment to match an approved verification
command anchored at its start. There is deliberately no leading-`cd` allowance:
`cd other-repo && npm test` would run tests elsewhere yet authorize this repo.

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
APPROVED_RE = re.compile(
    r"^(npm test|npm run test|npm run lint|npx jest|npx vitest|npx eslint|"
    r"pytest|python3 -m pytest|ruff check|flake8|mypy|"
    r"cargo test|cargo clippy|cargo check|go test|"
    r"make test|make lint|make check|shellcheck|"
    r"tsc --noEmit|\./node_modules/\.bin/tsc|bash -n)\b"
)
TEST_RE = re.compile(
    r"\b(npm test|npm run test|npx jest|npx vitest|pytest|cargo test|"
    r"go test|make test|bash -n)\b"
)
LINT_RE = re.compile(
    r"\b(npm run lint|npx eslint|tsc --noEmit|mypy|ruff check|flake8|"
    r"cargo clippy|cargo check|make lint|make check|shellcheck)\b"
)
# Match a git commit/push even with a path prefix (/usr/bin/git) or leading
# options (`git -C . commit`, `git -c k=v push`). Over-matching only widens the
# gate, which is the safe direction (R3-3).
COMMIT_PATTERN = re.compile(r"\bgit\b(?:\s+-\S+(?:\s+\S+)?)*\s+(?:commit|push)\b")

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


def main() -> None:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    if event.get("tool_name") != "Bash":
        return
    command = event.get("tool_input", {}).get("command", "")
    if not command:
        return

    session_id = event.get("session_id") or "default"
    cwd = event.get("cwd") or os.getcwd()
    root = project_root(cwd)
    hook_event = event.get("hook_event_name", "")

    if hook_event == "PostToolUse":
        if should_record(command):
            try:
                write_verification(command, state_file(session_id, root))
            except (StateDirError, OSError):
                pass  # cannot record safely; the gate will fail closed
    elif COMMIT_PATTERN.search(command):  # PreToolUse (default) — gate only
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


if __name__ == "__main__":
    main()
