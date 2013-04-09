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
TCCState *	T_PTROBJ
HERE

MODULE = XS::TCC        PACKAGE = XS::TCC::TCCState

TCCState *
new()
  CODE:
    RETVAL = tcc_new();
  OUTPUT: RETVAL

void
DESTROY(TCCState *self)
  CODE:
    tcc_delete(self);

MODULE = XS::TCC        PACKAGE = XS::TCC
