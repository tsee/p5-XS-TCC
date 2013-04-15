use strict;
use warnings;

use Test::More;
use XS::TCC qw(:all);

tcc_inline <<HERE;
HERE

pass("Alive");

tcc_inline
  typemap => ExtUtils::Typemaps->new,
  q{
  };

pass("Alive");

tcc_inline
  #warn_code => 1,
  q{
    int foo(int bar) {
      return bar * 2;
    }
  };

pass("Alive");

is(main::foo(3), 6, "Simple function is callable");

pass("Alive");

done_testing();
