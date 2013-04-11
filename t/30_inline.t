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
  q{
    int foo(int bar) {
      return bar * 2;
    }
  };

pass("Alive");

is(bar(3), 6, "Simple function is callable");

done_testing();
