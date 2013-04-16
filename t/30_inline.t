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

tcc_inline
  #warn_code => 1,
  q{
    AV *
    pairwise_sum (AV *left, AV *right)
    {
      size_t i;
      SV **elem;
      double val = 0;
      const size_t len_left  = av_len(left)+1;
      const size_t len_right = av_len(right)+1;
      const size_t len = len_left < len_right ? len_left : len_right;
      AV *retval = newAV();
      sv_2mortal((SV *)retval);
      av_extend(retval, len-1);
      for (i = 0; i < len; ++i) {
        val = 0;
        elem = av_fetch(left, i, 0);
        if (elem != NULL)
          val += SvNV(*elem);
        elem = av_fetch(right, i, 0);
        if (elem != NULL)
          val += SvNV(*elem);
        av_store(retval, i, newSVnv(val));
      }
      return retval;
    }
    int foo2(int bar) {
      return bar * 2;
    }
  };

pass("Alive");

is(foo2(2), 4);

pass("Alive");

is_deeply(pairwise_sum([1..10], [1..9]), [map $_*2, 1..9], "pairwise sum wrapped ok");

pass("Alive");

done_testing();
