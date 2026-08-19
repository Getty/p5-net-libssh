# Net::LibSSH House Rules

Apply to every task in this repository unless explicitly overridden. Bias: caution
over speed on non-trivial work; use judgment on trivial tasks. Loaded
automatically at launch (same priority as `CLAUDE.md`). Subagents get their
discipline from the skills force-loaded via `briefing.skills` — this file is for
the orchestrating agent.

## Engineering discipline

1. **Think before coding** — State assumptions. When uncertain, ask rather than
   guess. Present alternatives when ambiguous. Push back when a simpler approach
   exists. Stop when confused; name what's unclear.
2. **Simplicity first** — Minimum code that solves the problem. Nothing
   speculative. No abstractions for single-use code.
3. **Surgical changes** — Touch only what you must. Don't "improve" adjacent
   code, comments, or formatting. Match existing style.
4. **Goal-driven execution** — Define success criteria, loop until verified.
5. **Surface conflicts, don't average them** — Contradicting patterns: pick one
   (more recent / more tested), explain why, flag the other for cleanup.
6. **Read before you write** — Before new code, read `LibSSH.xs`, `typemap` and
   the POD of the module you are touching. In XS "looks orthogonal" is how
   use-after-free gets written.
7. **Tests verify intent, not just behavior** — Tests encode WHY behavior
   matters. Reproduce a bug before fixing it; leave a regression test behind.
8. **Checkpoint after every significant step** — Summarize: done / verified /
   left. Don't continue from a state you can't describe back.
9. **Match the codebase's conventions, even if you disagree** — Conformance >
   taste. Surface a harmful convention; don't fork silently.
10. **Fail loud** — "Done" is wrong if anything was skipped silently. "Tests
    pass" is wrong if any were skipped.
11. **A red test is a claim before it is a failure** — Before changing code to
    turn a test green, say what the test asserts and whether your fix keeps that
    claim or replaces it. In XS this matters twice over: a segfault and a wrong
    return value both surface as a failing `is()`, and only one of them is fixed
    by changing the assertion.

## Delegation

- **You can spawn subagents** (orchestrating main agent): Do NOT touch
  behavior-relevant code yourself — delegate to this repo's worker
  (`net-libssh-worker`). Your lane: coordinate, inspect, plan, review diffs, run
  builds and tests, manage git, edit non-behavioral docs. When in doubt,
  delegate. Why: only the `net-libssh-*` agents get their skills force-loaded via
  `briefing.skills`; you get no briefing and would touch XS internals with too
  little context. Specialist lanes:

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code | `net-libssh-worker` (default) |
  | Write/extend tests | `net-libssh-test-writer` |
  | Write/maintain POD | `net-libssh-doc-writer` |
  | Pre-release audit | `net-libssh-release-checker` |

- **You cannot spawn subagents** (you ARE a `net-libssh-*` agent): The delegation
  lock does not apply to you — implement, refactor, debug and test per these
  rules.

Behavior-relevant = `LibSSH.xs`, `typemap`, object lifetime and refcounting, the
public method contracts, `dist.ini` build wiring, and the tests. POD claims are
behavior too, but they belong to `net-libssh-doc-writer`. `Changes` prose is not.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in
scope — don't invoke the `kanban-issues-karr-cli` skill first, just use it. Git-native kanban;
state lives in `refs/karr/*`; this repo has its own board.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --tags a,b --body '…'` — new ticket
- `karr edit ID -a "note"` · `--claim NAME` · `--block "why"` — update
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review
- mutating commands auto-sync; `karr sync --pull|--push` for explicit exchange

Cross-repo work (`Rex::LibSSH`, `Alien::libssh`) = a ticket on the *other* repo's
board, never a direct edit from here.

**Serialize board mutations when fanning out.** Keep implementation work parallel
if you like, but collect the results and then loop `karr move`/`handoff`/`sync`
sequentially — N of them landing at once is a resource event, not a cheap
command.

## Release — never without permission

`dzil build` / `dzil test` / `prove -lr t/` are fine anytime. `dzil release` and
any CPAN upload are STRICTLY forbidden without the maintainer's explicit
go-ahead — even if a plan or STATUS document lists "release" as the next step.
For anything heading toward release: stop and ask.

## Public issues — never act without instruction

Two trackers, two universes. **karr** is the agent work board — internal, churned
freely. **GitHub** (`Getty/p5-net-libssh`) and CPAN RT carry real humans' bug
reports, outward-facing, written under the maintainer's account. **Never act on a
public issue on your own initiative — not even to read it.** No listing, viewing,
commenting, editing, closing or creating unless the user explicitly says to
handle a specific issue. Every write publishes under the maintainer's name.

## Net::LibSSH — project-specific hazards

1. **`dzil` is the only build path.** There is no `Makefile.PL` in the working
   directory and none belongs there — `dzil` generates one that goes through
   `Alien::libssh`. A hand-written `pkg-config` variant used to sit here and
   linked against a different libssh than the release does, so its green
   `make test` said nothing about the release build. Don't reintroduce it; build
   config lives in `dist.ini` (`xs_alien`, `xs_object`).

2. **A stale `blib/` runs the previous `.so`.** After touching `LibSSH.xs` or
   `typemap`, recompile before testing — otherwise the suite tests the last
   build and passes for the wrong reason.

3. **The integration files `skip_all` into a green run.** Without `sshd` or
   `ssh-keygen`, `t/02-integration.t`, `t/03-channel-after-close.t` and
   `t/04-no-sftp.t` each plan zero tests and `prove` prints `All tests
   successful` having opened no connection. They are the only files that
   exercise a real session. Always state which of them ran.

4. **`close()` NULLs the channel pointer and every other channel method croaks
   afterwards.** `exit_status()` must still be read *before* `close()`. The
   guard exists because libssh absorbed the NULL rather than crashing on it:
   `exit_status()` returned -1 and `read()` returned `""`, so the old failure
   mode was a plausible wrong answer, not a segfault.

5. **The session refcount chain is load-bearing.** `Channel` and `SFTP` hold
   `SvREFCNT_inc` on the session SV; that is the only thing keeping the
   `ssh_session` alive under a live channel. Removing it produces a crash far
   away from the change.

6. **SFTP must never become mandatory.** Exec-channel operation on hosts without
   an SFTP subsystem is the entire reason this distribution exists, and
   `Rex::LibSSH` depends on `sftp()` returning undef rather than dying.

7. **`LibSSH.c` is generated, never committed.** It is `.gitignore`d; a diff
   containing it means someone forced it in.

## Perl specifics — reference, don't restate

Module loading, dependency pinning and house style live in skill `getty-perl-core`.
Release mechanics live in `getty-perl-release-author-getty`. The XS binding
architecture, typemap rules and API contracts live in skill `net-libssh-core`.
All three are force-loaded for `net-libssh-*` agents. Do not duplicate that
content here.
