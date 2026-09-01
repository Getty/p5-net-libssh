requires 'Alien::libssh' => '0.002';

on configure => sub {
  requires 'Alien::libssh'    => '0.002';
  requires 'ExtUtils::MakeMaker' => '7.00';
};

on test => sub {
  requires 'Test::More' => '0.98';
};
