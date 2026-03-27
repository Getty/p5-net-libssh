use strict;
use warnings;
use ExtUtils::MakeMaker;

my $cflags = `pkg-config --cflags libssh 2>/dev/null`;
my $libs   = `pkg-config --libs   libssh 2>/dev/null`;
chomp $cflags;
chomp $libs;

WriteMakefile(
    NAME      => 'Net::LibSSH',
    VERSION   => '0.001',
    INC       => $cflags,
    LIBS      => [$libs],
    OBJECT    => 'LibSSH$(OBJ_EXT)',

);
