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

MODULE = XS::TCC        PACKAGE = XS::TCC
PROTOTYPES: DISABLE

REQUIRE: 3.18

TYPEMAP: <<HERE
TCCState * O_OBJECT

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
    if (cstr[len-1] != '\0') {
      croak("Need NUL terminated string!");
    }
    RETVAL = tcc_compile_string(self, cstr);
  OUTPUT: RETVAL

MODULE = XS::TCC        PACKAGE = XS::TCC
