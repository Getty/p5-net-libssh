# Net::LibSSH House Rules

Apply to every task here unless explicitly overridden. Bias: caution over speed on non-trivial work;
judgment on trivial ones. Subagents get their conventions from `briefing.skills` — skill content is
not restated here. Perl style: `getty-perl-core`; release: `getty-perl-release-author-getty`; XS:
`net-libssh-core`, `perl-xs`.

## Engineering discipline

1. **Think before coding** — State assumptions; ask rather than guess when uncertain; offer
   alternatives if ambiguous. Push back if a simpler approach exists; stop when confused, name
   what's unclear.
2. **Simplicity first** — Minimum code that solves the problem. Nothing speculative.
3. **Surgical changes** — Touch only what you must; don't "improve" adjacent code, comments or
   formatting. Match existing conventions even if you disagree; surface a harmful convention, don't
   fork silently.
4. **Read before you write** — Read `LibSSH.xs`, `typemap` and the POD of the module you touch: in
   XS "looks orthogonal" is how use-after-free gets written.
5. **Tests verify intent, not just behavior** — Reproduce a bug before fixing it and leave a
   regression test behind; before turning a test green, say what it asserts and whether your fix
   keeps or replaces that claim. In XS a segfault and a wrong return value both look like a failing
   `is()`.
6. **Fail loud** — "Done" is wrong if anything was skipped silently; "tests pass" is wrong if any
   were skipped. Surface uncertainty, don't hide it.
7. **Goal-driven execution with checkpoints** — Define success criteria, loop until verified,
   summarize done / verified / left; don't continue from a state you can't describe back.
8. **Surface conflicts, don't average them** — Contradicting patterns: pick one (more recent or more
   tested), explain why, flag the other for cleanup.

## Delegation

This rule depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): Do NOT touch behavior-relevant code —
  delegate. Your lane: coordinate, inspect, plan, review diffs, run builds and tests, edit prose
  docs. Why: only the `net-libssh-*` agents get their skills via `briefing.skills`; you get none.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-libssh-worker` (default) |
| Write/extend tests | `net-libssh-test-writer` |
| Write/maintain POD | `net-libssh-doc-writer` |
| Commits, `Changes`, card → done, pre-release audit | `net-libssh-release-manager` |

- **You cannot spawn subagents** (you ARE a `net-libssh-*` agent): The delegation lock does not
  apply — implement, refactor, debug and test per these rules.

Behavior-relevant = `LibSSH.xs`, `typemap`, object lifetime and refcounting, method contracts,
`dist.ini` wiring, the tests. POD claims belong to `net-libssh-doc-writer`; `Changes` prose is not.
**Only `net-libssh-release-manager` commits** — workers hand over a commit-ready tree and card.

## Net::LibSSH — project-specific hazards

- **`dzil` is the only build path** — no hand-written `Makefile.PL` or `pkg-config` variant; config
  lives in `dist.ini`.
- **A stale `blib/` runs the previous `.so`** — recompile after touching `LibSSH.xs` or `typemap`.
- **The integration files `skip_all` into a green run** — without `sshd`/`ssh-keygen`,
  `t/02-integration.t`, `t/03-channel-after-close.t` and `t/04-no-sftp.t` plan zero tests — always
  state which ran.
- **`close()` NULLs the channel pointer** — later channel methods croak; read `exit_status()` first.
- **The session refcount chain is load-bearing** — `Channel` and `SFTP` hold `SvREFCNT_inc` on the
  session SV; breaking it crashes far away.
- **SFTP must never become mandatory** — exec-channel work without an SFTP subsystem is why this
  distribution exists; `Rex::LibSSH` needs `sftp()` to return undef, not die.
- **`LibSSH.c` is generated, never committed** — a diff containing it means someone forced it in.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in scope — don't invoke
the `kanban-issues-karr-coordination` skill first, just use it. State lives in `refs/karr/*`.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --body '…'` · `karr edit ID -a "note" --block "why"`
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note` — review

Cross-repo work (`Rex::LibSSH`, `Alien::libssh`) is a ticket on the *other* repo's board, never a
direct edit from here. **Serialize board mutations when fanning out** — board writes sequentially.

## Release — never without permission

`dzil build` / `dzil test` / `prove -lr t/` are fine anytime. `dzil release` and any CPAN upload are
STRICTLY forbidden without the maintainer's explicit go-ahead — even if a plan or STATUS document
lists "release" next. Stop and ask.

## Public issues — never act without instruction

`karr` is the internal agent board, churned freely. GitHub (`Getty/p5-net-libssh`) and CPAN RT carry
real humans' bug reports, outward-facing. **Never act on a public issue on your own initiative — not
even to read it.** No listing, viewing, commenting, editing, closing or creating unless told to
handle a specific issue. Every write publishes under the maintainer's name.
