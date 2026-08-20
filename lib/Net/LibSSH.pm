# ABSTRACT: Perl binding for libssh — SSH without SFTP dependency

package Net::LibSSH;

use strict;
use warnings;

our $VERSION = '0.003';

use XSLoader;
XSLoader::load('Net::LibSSH', $VERSION);

=head1 SYNOPSIS

  use Net::LibSSH;

  my $ssh = Net::LibSSH->new;
  $ssh->option(host => 'server.example.com');
  $ssh->option(user => 'root');
  $ssh->option(port => 22);

  $ssh->connect or die "connect failed: " . $ssh->error;
  $ssh->auth_agent or die "auth failed: " . $ssh->error;

  my $ch = $ssh->channel;
  $ch->exec("uname -r");
  my $out = $ch->read;
  print "Kernel: $out";
  print "Exit: ", $ch->exit_status, "\n";

  # Optional SFTP (returns undef if SFTP subsystem not available)
  if (my $sftp = $ssh->sftp) {
    my $attr = $sftp->stat('/etc/hostname');
    print "size: $attr->{size}\n" if $attr;
  }

=head1 DESCRIPTION

L<Net::LibSSH> is a Perl XS binding for L<libssh|https://www.libssh.org/>.

Unlike L<Net::SSH2> (which wraps libssh2) and L<Net::OpenSSH> (which wraps
the system C<ssh> binary), this module links directly against B<libssh> — a
separate, actively maintained C library. The key difference for automation
use cases: file operations via L<Net::LibSSH::Channel> use SSH exec channels
and require no SFTP subsystem on the remote host.

SFTP is supported as an optional feature via L</sftp>: it returns C<undef>
gracefully when the remote server has no SFTP subsystem, rather than
crashing.

B<Note:> This module is not thread-safe and does not support fork. Use one
connection per process.

=head1 METHODS

=head2 new

  my $ssh = Net::LibSSH->new;

Creates a new session object.

=head2 option($key, $value)

  $ssh->option(host => 'server.example.com');
  $ssh->option(port => 22);
  $ssh->option(user => 'root');

Set a session option before connecting. Supported keys: C<host>, C<port>,
C<user>, C<knownhosts>, C<timeout>, C<compression>, C<log_verbosity>,
C<strict_hostkeycheck> (set to 0 to disable host key verification).

Croaks if C<$key> is not one of the keys above, or if libssh rejects the
resulting value. C<$value> is not validated on this side of the boundary —
numeric options go through Perl's ordinary numeric conversion, so a
non-numeric string silently becomes C<0> — and whether that ends up
croaking is entirely libssh's call, not something you can rely on
uniformly. For example, C<< port => 'nonsense' >> croaks (libssh rejects
port C<0>), while C<< timeout => 'nonsense' >> or
C<< log_verbosity => 'nonsense' >> are silently accepted as C<0>. Do not
read the absence of a croak here as validation.

=head2 connect

  $ssh->connect or die $ssh->error;

Connect to the host. Returns 1 on success, 0 on failure.

=head2 disconnect

  $ssh->disconnect;

Disconnect from the host. Every L<Net::LibSSH::Channel> and
L<Net::LibSSH::SFTP> object already opened on this session is invalidated
by the same call — libssh frees the channels as part of disconnecting.
From that point on, every method on such an object but C<close> croaks
with C<"session was disconnected">, a message distinct from a channel's
own C<"channel is closed"> so a caller can tell its own teardown from this
one; see L<Net::LibSSH::Channel/close>. Closing such a channel, or simply
letting it or an SFTP object go out of scope, is safe and does nothing.

C<< $ssh->channel >> and C<< $ssh->sftp >> called on a session that has
already disconnected return C<undef> rather than croaking — the same
graceful-failure contract they already have for any other failure to open.

The session itself is not reusable after C<disconnect>: measured against
libssh 0.10.6, calling L</connect> again on it does not reconnect, it times
out (C<"Timeout connecting to ...">), regardless of whether a channel was
ever opened on the session. That is a limitation of the underlying
library, not of this module, but treat C<disconnect>/C<connect> as
one-way — not a cycle you can repeat on the same session.

=head2 error

  my $msg = $ssh->error;

Return the last error message from libssh, or C<undef> — not the empty
string — when libssh has nothing to report.

=head2 auth_password($password)

  $ssh->auth_password('s3cr3t') or die $ssh->error;

=head2 auth_publickey($privkey_path)

  $ssh->auth_publickey('/root/.ssh/id_ed25519') or die $ssh->error;

=head2 auth_agent

  $ssh->auth_agent or die $ssh->error;

Authenticate via the SSH agent, falling back to the default key files
(public-key auto-authentication) whenever the agent attempt does not
succeed — not only when no agent is running, but also when a reachable
agent's authentication is rejected. A true return therefore does not by
itself prove that the agent was used; it only means one of the two methods
succeeded.

=head2 channel

  my $ch = $ssh->channel;

Open a new session channel. Returns a L<Net::LibSSH::Channel> object, or
C<undef> on failure — including when called on a session that has already
disconnected, see L</disconnect>. The returned channel keeps this session
alive on its own; see L<Net::LibSSH::Channel> for what that guarantees and
what it does not.

=head2 sftp

  my $sftp = $ssh->sftp;  # returns undef if SFTP not available

Open an SFTP session. Returns a L<Net::LibSSH::SFTP> object, or C<undef>
if the remote server does not support SFTP. This is the documented way to
detect SFTP availability — C<sftp> never throws for that reason, on this
or any other failure to open the session, including being called on a
session that has already disconnected, see L</disconnect>. Like
L</channel>, the returned object keeps this session alive on its own.

=head1 SEE ALSO

L<Net::LibSSH::Channel>, L<Net::LibSSH::SFTP>,
L<Alien::libssh>, L<Net::SSH2>

=cut

1;
