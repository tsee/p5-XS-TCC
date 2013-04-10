use strict;
use warnings;

use Test::More;
use XS::TCC;
use ExtUtils::Embed qw();
use File::Spec;

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

  is($comp->compile_string(<<'HERE'), 0, "Real code example compiles");
int
xs_tcc_test_foo(int a, int b)
{
  return a + b;
}
HERE
  is($comp->relocate(), 0);
  isa_ok($comp->get_symbol("xs_tcc_test_foo"), "XS::TCC::TCCSymbol");
}

SCOPE: {
  my $include_dir = (-d 't' ? File::Spec->curdir : File::Spec->updir);
  my $comp = XS::TCC::TCCState->new;
  $comp->set_options(ExtUtils::Embed::ccopts() . " -I$include_dir");

  is($comp->compile_string(<<'HERE'), 0, "Real XS example compiles");
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#include <ppport.h>

void
xs_tcc_test_bar(pTHX_ CV *cv)
{
  dVAR; dXSARGS; dXSTARG;
  IV rv;

  if (items != 2)
    croak("Need two params");

  rv = SvIV(ST(0)) + SvIV(ST(1));

  {
    XSprePUSH; PUSHi((IV)rv);
  }

  XSRETURN(1);
}
HERE
  is($comp->relocate(), 0);
  my $sym = $comp->get_symbol("xs_tcc_test_bar");
  isa_ok($sym, "XS::TCC::TCCSymbol");
  my $sub = $sym->install_as_xsub("main::bar");
  ok(!eval {$sub->(); 1} && $@);
  is($sub->(3, 5), 8, "XSUB can add!");
}

pass("Alive");

done_testing();
