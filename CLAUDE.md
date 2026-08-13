# Net::LibSSH

XS Perl binding for libssh — SSH library without SFTP dependency.

## What It Is

Net::LibSSH wraps the C libssh library (NOT libssh2). Key difference from
Net::SSH2: file operations use SSH exec channels, not SFTP. The SFTP support
is optional and returns `undef` gracefully when the subsystem is absent — that
is what `Rex::LibSSH` uses downstream to detect SFTP availability.

## Module Structure

- `Net::LibSSH` — session: connect, auth, channel(), sftp()
- `Net::LibSSH::Channel` — exec, read, write, send_eof, exit_status, close
- `Net::LibSSH::SFTP` — stat() (optional, undef if no SFTP subsystem)

All implementation lives in `LibSSH.xs`; the three `.pm` files hold `$VERSION`,
`XSLoader::load` and POD.

## Usage

```perl
use Net::LibSSH;

my $ssh = Net::LibSSH->new;
$ssh->option(host => 'server.example.com');
$ssh->option(user => 'root');
$ssh->connect or die $ssh->error;
$ssh->auth_agent or die $ssh->error;

my $ch = $ssh->channel;
$ch->exec('uname -r');
print $ch->read;
print "exit: ", $ch->exit_status, "\n";   # before close() — close() NULLs the channel
$ch->close;
```

## Build

This is an XS module — requires a C compiler and libssh headers, supplied by
`Alien::libssh`. The canonical build is Dist::Zilla (`[@Author::GETTY]` with
`xs_alien = Alien::libssh`, `xs_object = LibSSH`):

```bash
dzil build
dzil test
```

The `Makefile.PL` in the working directory is untracked and hand-written against
`pkg-config`; it is **not** the file `dzil` generates. It is fine for a quick
local compile, but a green `make test` is not evidence about the release build.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it
yourself — principle and lane are in `.claude/rules/net-libssh-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-libssh-worker` (default) |
| Write/extend tests | `net-libssh-test-writer` |
| Write/maintain POD | `net-libssh-doc-writer` |
| Pre-release audit | `net-libssh-release-checker` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the
main agent delegates rather than loading them. Skill sources live under
`.claude/skills/` — `net-libssh-core` holds the XS binding architecture
(`sv_magicext`/MGVTBL lifecycle, the per-type typemap and its escaping rules,
the session refcount chain, the API contracts); `perl-core`,
`perl-release-author-getty`, `perl-release-dist-ini` and `karr` are hardlinked
shared skills.
