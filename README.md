# Net::LibSSH

Perl XS binding for [libssh](https://www.libssh.org/) — SSH without SFTP dependency.

Unlike [Net::SSH2](https://metacpan.org/pod/Net::SSH2) (wraps libssh2) and [Net::OpenSSH](https://metacpan.org/pod/Net::OpenSSH) (wraps the system `ssh` binary), this module links directly against **libssh** — a separate, actively maintained C library. File operations use SSH exec channels and require **no SFTP subsystem** on the remote host.

This makes it the right choice for minimal containers, embedded systems, and Kubernetes nodes (where SFTP is often absent).

## Synopsis

```perl
use Net::LibSSH;

my $ssh = Net::LibSSH->new;
$ssh->option(host => 'server.example.com');
$ssh->option(user => 'root');
$ssh->option(port => 22);

$ssh->connect or die "connect failed: " . $ssh->error;
$ssh->auth_agent or die "auth failed: " . $ssh->error;

my $ch = $ssh->channel;
$ch->exec("uname -r");
print "Kernel: ", $ch->read;
print "Exit: ", $ch->exit_status, "\n";   # before close() -- see the POD

# SFTP is optional — returns undef if not available on the remote
if (my $sftp = $ssh->sftp) {
    my $attr = $sftp->stat('/etc/hostname');
    print "size: $attr->{size}\n" if $attr;
}
```

## Features

- Direct libssh C library binding (XS)
- No SFTP subsystem required on the remote host
- SSH agent authentication, public key, and password auth
- Exec channels via `Net::LibSSH::Channel`
- Optional SFTP via `Net::LibSSH::SFTP` (gracefully returns `undef` when unavailable)
- Powers the [Rex::LibSSH](https://metacpan.org/pod/Rex::LibSSH) connection backend

## Installation

```
cpanm Net::LibSSH
```

[Alien::libssh](https://metacpan.org/pod/Alien::libssh) supplies the C library: it uses a system `libssh` when one is installed (`libssh-dev` on Debian/Ubuntu, `libssh-devel` on RHEL/Fedora) and builds one from source otherwise. A C compiler is needed either way.

## See Also

- [Net::LibSSH::Channel](https://metacpan.org/pod/Net::LibSSH::Channel)
- [Net::LibSSH::SFTP](https://metacpan.org/pod/Net::LibSSH::SFTP)
- [Alien::libssh](https://metacpan.org/pod/Alien::libssh)
- [Rex::LibSSH](https://metacpan.org/pod/Rex::LibSSH)

## Author

Torsten Raudssus `<getty@cpan.org>`

## License

This software is copyright (c) 2026 by Torsten Raudssus. This is free software; you can redistribute it and/or modify it under the same terms as the Perl 5 programming language system itself.
