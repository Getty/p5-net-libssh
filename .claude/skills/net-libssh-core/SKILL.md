---
name: net-libssh-core
description: Load before editing Net::LibSSH — the XS surface over libssh, the sv_magicext object lifecycle that replaces DESTROY, the typemap, the session refcount chain, the dzil-only build path.
metadata:
  type: project
---

# Net::LibSSH — core architecture

This skill is loaded into every `net-libssh-*` agent's context before its first
turn. Do not duplicate its content in the agent body.

## What this distribution is

An XS binding to **libssh** (`https://www.libssh.org/`) — *not* libssh2, which is
what `Net::SSH2` wraps, and not the system `ssh` binary, which is what
`Net::OpenSSH` drives. The C library comes from `Alien::libssh`.

The product claim: **file and command operations run over SSH exec channels and
need no SFTP subsystem on the remote host.** SFTP exists as an optional extra and
degrades to `undef` rather than dying. If a code path in here ever makes SFTP
mandatory, the distribution has lost the thing it exists for.

Downstream consumer: `Rex::LibSSH` (`~/dev/perl/getty-rex-libssh`), which reimplements
Rex's four connection interfaces on top of this module, for Hetzner dedicated
servers whose sshd ships without `Subsystem sftp`. `Rex::LibSSH` pins this
distribution in its `cpanfile`, so a behaviour change here reaches its deploys.

Upstream: `Alien::libssh` (`~/dev/perl/p5-alien-libssh`), also Getty-authored.

## Module map

| File | Owns |
|---|---|
| `LibSSH.xs` | **all** implementation — three `MODULE`/`PACKAGE` sections in one file |
| `typemap` | the three named typemap entries; INPUT/OUTPUT for every object crossing the XS boundary |
| `lib/Net/LibSSH.pm` | `XSLoader::load`, `$VERSION`, POD for the session API. No logic. |
| `lib/Net/LibSSH/Channel.pm` | POD only — the package exists in XS, this file documents it |
| `lib/Net/LibSSH/SFTP.pm` | POD only — same |

The three `.pm` files each carry their own `our $VERSION`; there is no shared
version module. All three must move together.

`LibSSH.c` is generated from `LibSSH.xs` by xsubpp and is **not** committed.

## Object lifecycle — `sv_magicext` + MGVTBL, never DESTROY

Objects are stored with `sv_magicext` under a **type-specific `MGVTBL`**. The C
pointer lives in `mg->mg_ptr`; Perl's GC calls `svt_free` when the SV is
collected.

```c
static int nlss_session_free(pTHX_ SV *sv, MAGIC *mg) {
    NLSS_Session *self = (NLSS_Session *)(void *)mg->mg_ptr;
    if (self->session) { ssh_disconnect(self->session); ssh_free(self->session); }
    Safefree(self);
    return 0;
}
static const MGVTBL Net__LibSSH_magic = { .svt_free = nlss_session_free };
```

Why this and not `sv_setref_pv` + a `DESTROY` method:

- **No `DESTROY` in XS.** `svt_free` fires even when `DESTROY` is overridden and
  during global destruction.
- **Strict type safety.** `mg_findext(..., &Net__LibSSH_magic)` matches only magic
  carrying that *exact vtable address* — two types can never be confused, and a
  hand-blessed hashref croaks at the boundary instead of segfaulting.
- **Thread-safe cleanup** — the vtable is the right hook for `CLONE_PARAMS` if it
  is ever needed.

Never add a `DESTROY` sub, in XS or in the `.pm` files.

## The session refcount chain — do not break it

`NLSS_Channel` and `NLSS_SFTP` each hold `SV *session_sv`, set with
`SvREFCNT_inc(ST(0))` at construction and released with `SvREFCNT_dec` in their
`svt_free`.

That increment is meant to guarantee the `ssh_session` outlives every channel
opened on it. Any new object type that borrows the session must take the same
reference.

**Take the reference on `SvRV(ST(0))`, never on `ST(0)`.** `ST(0)` is the
reference scalar — the `$ssh` variable's own SV; the referent is the blessed
magic-bearing SV the typemap operates on and whose `svt_free` calls `ssh_free()`.
Through 0.002 the increment was on `ST(0)`, which keeps the referent alive only
while the RV still points at it:

| what happens to the session variable | through 0.002 | now |
|---|---|---|
| goes out of scope | worked | works |
| `undef $ssh` | **SIGSEGV** | works |
| `$ssh = anything_else` | **SIGSEGV** | works |

Dereferencing `ST(0)` there is safe: the typemap INPUT block runs before `CODE`
and croaks unless `SvROK(_sv) && SvMAGICAL(SvRV(_sv))`, and OUTPUT overwrites
`ST(0)` only afterwards. The free side needs nothing special — `SvREFCNT_dec` is
symmetric with whatever was stored.

Note which case survived the bug: the one a test reaches for first. A refcount
mistake here is invisible under scope-exit and fatal under `undef`.
`t/07-refcount-chain.t` covers all three ways of losing the variable, times both
object types, each in a forked child.

## Struct and typedef layout

Two layers of typedef, deliberately:

```c
typedef struct { ssh_session session; } NLSS_Session;   /* named, so Newxz has a type */
typedef NLSS_Session *Net__LibSSH;                      /* pointer typedef for xsubpp */
```

`NLSS_Session` is named so `Newxz(RETVAL, 1, NLSS_Session)` has a concrete size.
`Net__LibSSH` is the pointer typedef xsubpp uses in generated C — `Net__LibSSH
self` there corresponds to `Net::LibSSH self` in the XS signature. Because these
are *pointer* typedefs, XS signatures need no `*`.

## Typemap — per-type entries, INPUT via `mg_findext`, OUTPUT via `sv_magicext`

```
Net::LibSSH          T_NET_LIBSSH
Net::LibSSH::Channel T_NET_LIBSSH_CHANNEL
Net::LibSSH::SFTP    T_NET_LIBSSH_SFTP
```

INPUT looks for magic with the matching vtable and croaks otherwise. OUTPUT
builds the blessed magic SV. So `new()`, `channel()` and `sftp()` only ever set
`RETVAL` — blessing is entirely the typemap's job. Do not bless by hand.

### Escaping — the parse error that costs an hour

xsubpp evaluates typemap INPUT/OUTPUT templates as **Perl double-quoted
strings**. Every `"` that must reach the generated C has to be written `\"`; an
unescaped one ends the Perl string early and the failure surfaces as an
unrelated C syntax error.

```
# Wrong:    sv_magicext(newSVrv($arg, "Net::LibSSH"), ...);
# Correct:  sv_magicext(newSVrv($arg, \"Net::LibSSH\"), ...);
```

### Why not the generic `T_MAGICEXT` with `&${type}_magic`

`Crypt::OpenSSL3` uses one `T_MAGICEXT` entry and lets `${type}` expand with the
`::` → `__` transformation. **That transformation only exists in xsubpp ≥ 3.60**
(hence their `REQUIRE: 3.60`). On xsubpp 3.45 — Perl 5.36 — `${type}` is still
`Net::LibSSH`, which is not a C identifier. The per-type entries here hardcode
the vtable pointers instead and work on both.

### Why not `T_PTROBJ`

It appends `Ptr` to the class name (`Net__LibSSHPtr`) and uses
`sv_setref_pv`/`INT2PTR`: no `svt_free`, no vtable type check. Don't.

### Why not `COUNTING_TYPE` / `DUPLICATING_TYPE` macros

Those generate `make_T`/`get_T` helpers for many types with refcounted or
duplicable C objects. libssh has no `ssh_session_dup` and no `ssh_session_up_ref`,
and with three types the macro machinery costs more than it saves.

## XS house rules

- **`#define NEED_mg_findext` before `ppport.h`** — supplies `mg_findext` on
  Perl < 5.14.
- **`#define undef &PL_sv_undef`** — shorthand used throughout for returning
  undef.
- **No `PREINIT`.** Declare variables directly in `CODE` blocks.
- **`PROTOTYPES: DISABLE`** is written once after the first `MODULE =` line;
  xsubpp inherits it for the later packages in the same file.
- **Every channel method except `close` opens with
  `nlss_channel_check_open()`.** A closed channel has `self->channel == NULL`,
  and libssh absorbs a NULL channel rather than crashing on it: before the guard
  `exit_status()` returned -1 and `read()` returned `""`. The failure mode is a
  plausible wrong answer, not a segfault, so a missing guard on a new method is
  invisible in testing. `close()` is the exception — it must stay idempotent for
  `svt_free`.
- **`XSRETURN_UNDEF` bypasses the OUTPUT section.** That is how `channel()`,
  `sftp()` and `stat()` return undef instead of an object. It also means
  `RETVAL` must not have been allocated yet when you take that branch —
  otherwise the allocation leaks. Check the C resource is freed on that path
  (`ssh_channel_free` / `sftp_free`) before returning.

## API contracts a caller depends on

These are behaviour, not style. Changing one is a breaking change for
`Rex::LibSSH`.

- **`sftp()` returns `undef`, never dies**, when the server has no SFTP
  subsystem. This is the documented detection mechanism downstream.
- **`stat()` returns `undef`** for a missing or inaccessible path — never a
  half-populated hashref.
- **`connect()` / `auth_*()` return 1 or 0 and do not die.** The message goes
  through `error()`, which returns `undef` — not the empty string — when libssh
  has nothing to say. A refused port must return 0, not croak.
- **`auth_agent()` silently falls back to `ssh_userauth_publickey_auto`** when
  the agent is missing or refuses. A return of 1 is not evidence that an agent
  was used.
- **`option()` croaks on an unknown key, and again on a value libssh rejects.**
  The key set is a closed `strcmp` chain; extending it means extending the POD
  too.

  | key | libssh option | conversion |
  |---|---|---|
  | `host` | `SSH_OPTIONS_HOST` | `SvPV_nolen` |
  | `user` | `SSH_OPTIONS_USER` | `SvPV_nolen` |
  | `port` | `SSH_OPTIONS_PORT` | `SvUV` |
  | `knownhosts` | `SSH_OPTIONS_KNOWNHOSTS` | `SvPV_nolen` |
  | `timeout` | `SSH_OPTIONS_TIMEOUT` | `SvIV` |
  | `compression` | `SSH_OPTIONS_COMPRESSION` | `SvPV_nolen` |
  | `log_verbosity` | `SSH_OPTIONS_LOG_VERBOSITY` | `SvIV` |
  | `strict_hostkeycheck` | `SSH_OPTIONS_STRICTHOSTKEYCHECK` | `SvTRUE` |

  The Perl-side conversion is silent: `SvUV`/`SvIV` of a non-numeric string is 0,
  with a runtime warning at most. Whether that becomes an error is libssh's
  decision, and it is not uniform — measured, not inferred:

  ```
  port          => 'nonsense'   croaks: Invalid argument in ssh_options_set
  timeout       => 'nonsense'   accepted silently as 0
  log_verbosity => 'nonsense'   accepted silently as 0
  ```

  `port` only croaks because libssh rejects port 0 in particular. There is no
  validation on this side of the boundary, so do not read the croak as one.
- **`read()` with no argument (or `-1`) slurps until EOF.** `read(undef)` is a
  trap: `SvIV(undef)` is 0, so it takes the fixed-length branch with length 0,
  reads nothing and returns the empty string. Both branches end on
  `ssh_channel_read() <= 0` and yield a string either way, so **`read()` cannot
  distinguish EOF from a read error** — neither returns undef, neither croaks.
  Documented in the POD; keep it documented.
- **`exit_status()` returns -1 until the remote process has exited.** The POD
  tells callers to drain the output first, but that is advice, not a
  requirement: on libssh 0.10.6, `ssh_channel_get_exit_status()` pumps the
  session's packet loop itself, so calling it first returns the right code and
  leaves the undrained output buffered for a later `read()`. Measured in
  `t/06-exit-status-ordering.t`, which guards every such call with `alarm()`
  precisely because a libssh build that blocks instead would hang the suite
  rather than fail it. Treat the drain-first order as the supported one.
- **`close()` sets `self->channel = NULL`; every other channel method croaks
  from then on.** The message is `"<fully qualified method>: channel is
  closed"`. `exit_status()` must still be read *before* `close()` — it now fails
  loudly instead of returning -1, which a caller cannot tell apart from "the
  process has not exited yet". `close()` itself is idempotent and deliberately
  unguarded, because `svt_free` walks the same path when the SV is collected.
- **`disconnect()` invalidates every live channel and SFTP session — and
  currently crashes.** `ssh_disconnect()` walks `session->channels` and frees
  them inside libssh, so every `NLSS_Channel` keeps a dangling `ssh_channel`.
  `nlss_channel_check_open()` does not catch this: the pointer is non-NULL, it
  just points at freed memory. Using the channel segfaults, and so does merely
  dropping it, because `nlss_channel_free` calls `ssh_channel_send_eof` on the
  freed channel. karr #9; unfixed, and it needs a design decision rather than a
  guard.
- **A channel runs one command per lifetime.** `exec` is called once; a second
  command needs a new `$ssh->channel`.
- **Not fork-safe, not thread-safe.** One session per process, as the POD says.

## Build — dzil is the only path

The build is Dist::Zilla: `[@Author::GETTY]` with `xs_alien =
Alien::libssh` and `xs_object = LibSSH` in `dist.ini`. It generates a
`Makefile.PL` that resolves flags via `Alien::libssh->cflags` / `->libs`.

```bash
dzil build     # generates Makefile.PL, compiles, produces the tarball
dzil test      # the suite as it will be released
prove -lr t/   # needs a Makefile-built blib/ first
```

**There is deliberately no `Makefile.PL` in the working directory.** A
hand-written one resolving flags via `pkg-config` used to sit here; it built
against whatever libssh `pkg-config` found, which is not what the release links
against, so a green local `make test` was no evidence about the release. Don't
reintroduce it — build configuration belongs in `dist.ini`, and `dzil`
overwrites any `Makefile.PL` in place anyway.
