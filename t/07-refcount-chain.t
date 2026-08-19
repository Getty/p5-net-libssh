use strict;
use warnings;
use lib 't/lib';
use Test::More;
use TestSSHD;
use Net::LibSSH;
use POSIX ();

# The session refcount chain is supposed to be the only thing keeping the
# underlying ssh_session alive once the Perl-level session variable goes
# away while a channel opened on it is still in use (net-libssh-core
# skill: "NLSS_Channel and NLSS_SFTP each hold SV *session_sv, set with
# SvREFCNT_inc(ST(0)) at construction ... That increment is the only thing
# guaranteeing the ssh_session outlives every channel opened on it.").
#
# This test reproduces exactly that scenario: create a channel, undef the
# session variable, keep using the channel.
#
# It runs the reproduction in a forked child so that if the chain is
# broken and this segfaults, only the child dies -- this test process (and
# the rest of the suite) survives to report it as a normal, if alarming,
# test result instead of taking `prove` down with it.

my $srv = TestSSHD->start;
plan skip_all => 'sshd or ssh-keygen not available' unless $srv;

pipe(my $rd, my $wr) or plan skip_all => "pipe: $!";

my $pid = fork();
plan skip_all => "fork: $!" unless defined $pid;

if ($pid == 0) {
    # child
    close $rd;
    my $ok = eval {
        my $ssh = Net::LibSSH->new;
        $ssh->option(host       => $srv->host);
        $ssh->option(port       => $srv->port);
        $ssh->option(user       => scalar getpwuid($<));
        $ssh->option(knownhosts => '/dev/null');
        $ssh->connect
            or die 'connect: ' . ($ssh->error // '') . "\n";
        $ssh->auth_publickey($srv->client_key)
            or die 'auth: ' . ($ssh->error // '') . "\n";

        my $ch = $ssh->channel;
        die "channel() returned undef\n" unless defined $ch;

        # The point of the test: drop the only Perl-level reference to the
        # session while the channel opened on it is still alive, then keep
        # using the channel.
        undef $ssh;

        $ch->exec('echo refcount_chain_' . $$);
        my $out = $ch->read;
        chomp $out;
        my $status = $ch->exit_status;
        $ch->close;
        print {$wr} "$out|$status\n";
        1;
    };
    print {$wr} "ERROR|$@\n" unless $ok;
    close $wr;
    # POSIX::_exit skips Perl's global destruction. $srv (TestSSHD) was
    # inherited from the parent across fork() and shares the parent's sshd
    # pid; letting this child run $srv's DESTROY too would send a second
    # SIGTERM and waitpid() a process the parent still owns.
    POSIX::_exit($ok ? 0 : 1);
}

close $wr;
my $line = <$rd>;
close $rd;
waitpid($pid, 0);
my $signal = $? & 127;

TODO: {
    local $TODO = 'session refcount chain bug: LibSSH.xs channel()/sftp() call '
        . 'SvREFCNT_inc(ST(0)), which refcounts the *reference scalar* (the '
        . '$ssh variable\'s own SV), not SvRV(ST(0)), the blessed magic-bearing '
        . 'object it points to. undef $ssh still drops the referent\'s refcount '
        . 'to 0 and frees the ssh_session while a live channel still points at '
        . 'it. Reproducibly segfaults; needs a worker fix, not a test fix.';

    if ($signal) {
        fail('channel used after its session variable goes undef does not crash');
        my $signame = $signal == 11 ? 'SIGSEGV' : $signal == 6 ? 'SIGABRT' : "signal $signal";
        diag("child was killed by $signame -- the session refcount chain did not "
            . "keep the underlying ssh_session alive while a channel opened on it "
            . "was still in use.");
    }
    else {
        my $expected = "refcount_chain_$pid|0\n";
        my $got_desc = defined $line ? $line : '(undef -- child produced no output on the pipe)';
        ok defined($line) && $line eq $expected,
            'channel stays usable and returns correct output/exit_status after its session variable is undef-ed';
        diag("expected [$expected], got [$got_desc]")
            unless defined($line) && $line eq $expected;
    }
}

done_testing;
