# ABSTRACT: Optional SFTP session for Net::LibSSH

package Net::LibSSH::SFTP;

use strict;
use warnings;

=head1 DESCRIPTION

L<Net::LibSSH::SFTP> wraps an SFTP session opened over an existing SSH
connection. Instances are created via L<Net::LibSSH/sftp>.

If the remote server has no SFTP subsystem, L<Net::LibSSH/sftp> returns
C<undef> instead of throwing — callers should always check the return value.

=head1 METHODS

=head2 stat($path)

  my $attr = $sftp->stat('/etc/hostname');
  if ($attr) {
    print "size: $attr->{size}, mode: $attr->{mode}\n";
  }

Returns a hashref with keys C<name>, C<size>, C<uid>, C<gid>, C<mode>,
C<atime>, C<mtime>, or C<undef> if the path does not exist.

=head1 SEE ALSO

L<Net::LibSSH>

=cut

1;
