use strict;
use warnings;

use Test::More;
use XS::TCC;

pass("Alive");

SCOPE: {
  my $comp = XS::TCC::TCCState->new;
  isa_ok($comp, "XS::TCC::TCCState");
}

pass("Alive");

SCOPE: {
  my $comp = XS::TCC::TCCState->new;
  my $i = $comp->compile_string("");
  is($i, 0);
}

pass("Alive");

done_testing();
