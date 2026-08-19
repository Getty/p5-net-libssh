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

That increment is the only thing guaranteeing the `ssh_session` outlives every
channel opened on it. Drop it and a session going out of scope while a channel is
still live frees the C session under the channel — a use-after-free that shows up
as an unrelated crash much later. Any new object type that borrows the session
must take the same reference.

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
  through `error()`. A refused port must return 0, not croak.
- **`option()` croaks on an unknown key.** The key set is closed and enumerated
  in the XS `strcmp` chain; extending it means extending the POD too.
- **`read()` with no argument (or `-1`) slurps until EOF.** `read(undef)` is a
  trap: `SvIV(undef)` is 0, so it reads nothing and returns the empty string.
  Documented in the POD; keep it documented.
- **`exit_status()` returns -1 until the remote process has exited** — read the
  output first.
- **`close()` sets `self->channel = NULL`.** Every other channel method
  dereferences that pointer straight into libssh. Treat any channel call after
  `close` as use-after-free; in particular `exit_status()` must be read
  *before* `close()`. `close()` itself is idempotent.
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
