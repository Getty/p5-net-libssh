# ABSTRACT: SSH exec channel for Net::LibSSH

package Net::LibSSH::Channel;

use strict;
use warnings;

=head1 DESCRIPTION

L<Net::LibSSH::Channel> represents an open SSH session channel. Instances
are created via L<Net::LibSSH/channel> and must not be constructed directly.

=head1 METHODS

=head2 exec($command)

  $ch->exec('uname -r') or die "exec failed";

Execute a command on the remote host. Returns 1 on success, 0 on failure.

=head2 read([$length [, $is_stderr]])

  my $stdout = $ch->read;          # slurp all stdout
  my $chunk  = $ch->read(4096);    # read up to 4096 bytes
  my $stderr = $ch->read(-1, 1);   # slurp stderr

Read output from the channel. Without arguments, reads until EOF.

=head2 write($data)

  $ch->write("input\n");

Write data to the channel's standard input.

=head2 send_eof

  $ch->send_eof;

Signal end-of-input to the remote command.

=head2 eof

  $ch->send_eof;
  while (!$ch->eof) { ... }

Returns true when the remote side has closed the channel.

=head2 exit_status

  my $rc = $ch->exit_status;

Returns the exit status of the last command (after it has finished).

=head2 close

  $ch->close;

Close the channel explicitly. Also called automatically by C<DESTROY>.

=head1 SEE ALSO

L<Net::LibSSH>

=cut

1;
