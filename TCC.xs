#define PERL_NO_GET_CONTEXT

/* For versions of ExtUtils::ParseXS > 3.04_02, we need to
 * explicitly enforce exporting of XSUBs since we want to
 * refer to them using XS(). This isn't strictly necessary,
 * but it's by far the simplest way to be backwards-compatible.
 */
/* #define PERL_EUPXS_ALWAYS_EXPORT */

#include "EXTERN.h"
#include "perl.h"

#include "XSUB.h"
#include "ppport.h"

#include <libtcc.h>

typedef void tccsymbol;

MODULE = XS::TCC        PACKAGE = XS::TCC
PROTOTYPES: DISABLE

REQUIRE: 3.18

TYPEMAP: <<HERE
TCCState * O_OBJECT
tccsymbol * O_OBJECT

OUTPUT
O_OBJECT
  sv_setref_pv( $arg, CLASS, (void*)$var );

INPUT

O_OBJECT
  if( sv_isobject($arg) && (SvTYPE(SvRV($arg)) == SVt_PVMG) )
    $var = ($type)SvIV((SV*)SvRV( $arg ));
  else{
    warn( \"${Package}::$func_name() -- $var is not a blessed SV reference\" );
    XSRETURN_UNDEF;
  }
HERE

MODULE = XS::TCC        PACKAGE = XS::TCC::TCCState

TCCState *
new(const char *CLASS)
  CODE:
    RETVAL = tcc_new();
    /* for now, always set output type to memory */
    tcc_set_output_type(RETVAL, TCC_OUTPUT_MEMORY);
  OUTPUT: RETVAL

void
DESTROY(TCCState *self)
  CODE:
    tcc_delete(self);

int
compile_string(TCCState *self, SV *code)
  PREINIT:
    STRLEN len;
    char *cstr;
  CODE:
    cstr = SvPV(code, len);
    RETVAL = tcc_compile_string(self, cstr);
  OUTPUT: RETVAL

tccsymbol *
get_symbol(TCCState *self, const char *name)
  PREINIT:
    const char *CLASS = "XS::TCC::TCCSymbol";
    /* Note: Perl symbol objects must not live longer than TCCStates
     *       or they become invalid. */
  CODE:
    RETVAL = tcc_get_symbol(self, name);
    if (RETVAL == NULL)
      croak("Symbol '%s' not found!", name);
  OUTPUT: RETVAL

int
relocate(TCCState *self)
  CODE:
    RETVAL = tcc_relocate(self, TCC_RELOCATE_AUTO);
  OUTPUT: RETVAL

int
set_options(TCCState *self, const char *opt)
  CODE:
    RETVAL = tcc_set_options(self, opt);
  OUTPUT: RETVAL


MODULE = XS::TCC        PACKAGE = XS::TCC::TCCSymbol

CV *
install_as_xsub(tccsymbol *self, char *full_subname = NULL)
  PREINIT:
    XSUBADDR_t sub;
  CODE:
    sub = (XSUBADDR_t)self;
    RETVAL = newXS(full_subname, sub, "anon");
    sv_2mortal((SV *)RETVAL);
  OUTPUT: RETVAL

MODULE = XS::TCC        PACKAGE = XS::TCC
