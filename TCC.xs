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

typedef void xstcc_symbol;

typedef struct {
  TCCState *tccstate;
  CV *error_callback;
#ifdef PERL_IMPLICIT_CONTEXT
  tTHX perl_thread_context;
#endif
} xstcc_state;

void
xstcc_error_func(void *opaque, const char *msg)
{
  xstcc_state *state = (xstcc_state *)opaque;
#ifdef PERL_IMPLICIT_CONTEXT
  tTHX my_perl = state->perl_thread_context;
#endif

  if (state->error_callback != NULL) {
    dSP;
    dXSTARG;

    PUSHMARK(SP);
    XPUSHp(msg, strlen(msg));
    PUTBACK;

    call_sv((SV *)state->error_callback, G_DISCARD);
  }
  else
    croak("%s", msg);
}

MODULE = XS::TCC        PACKAGE = XS::TCC
PROTOTYPES: DISABLE

REQUIRE: 3.18

TYPEMAP: <<HERE
TCCState * O_OBJECT
xstcc_state * O_OBJECT
xstcc_symbol * O_OBJECT

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

xstcc_state *
new(const char *CLASS)
  CODE:
    Newx(RETVAL, 1, xstcc_state);
    RETVAL->tccstate = tcc_new();
    RETVAL->error_callback = NULL;
    RETVAL->perl_thread_context = aTHX;
    /* for now, always set output type to memory */
    tcc_set_output_type(RETVAL->tccstate, TCC_OUTPUT_MEMORY);
    /* croaks by default */
    tcc_set_error_func(RETVAL->tccstate, (void *)RETVAL, xstcc_error_func);
  OUTPUT: RETVAL

void
DESTROY(xstcc_state *self)
  CODE:
    tcc_delete(self->tccstate);
    SvREFCNT_dec(self->error_callback); /* has a NULL check */
    Safefree(self);

int
compile_string(xstcc_state *self, SV *code)
  PREINIT:
    STRLEN len;
    char *cstr;
  CODE:
    cstr = SvPV(code, len);
    RETVAL = tcc_compile_string(self->tccstate, cstr);
  OUTPUT: RETVAL

xstcc_symbol *
get_symbol(xstcc_state *self, const char *name)
  PREINIT:
    const char *CLASS = "XS::TCC::TCCSymbol";
    /* Note: Perl symbol objects must not live longer than TCCStates
     *       or they become invalid. */
  CODE:
    RETVAL = tcc_get_symbol(self->tccstate, name);
    if (RETVAL == NULL)
      croak("Symbol '%s' not found!", name);
  OUTPUT: RETVAL

int
relocate(xstcc_state *self)
  CODE:
    RETVAL = tcc_relocate(self->tccstate, TCC_RELOCATE_AUTO);
  OUTPUT: RETVAL

int
set_options(xstcc_state *self, const char *opt)
  CODE:
    RETVAL = tcc_set_options(self->tccstate, opt);
  OUTPUT: RETVAL

void
set_error_callback(xstcc_state *self, CV *callback)
  CODE:
    SvREFCNT_inc(callback);
    SvREFCNT_dec(self->error_callback); /* includes NULL check */
    self->error_callback = callback;

MODULE = XS::TCC        PACKAGE = XS::TCC::TCCSymbol

CV *
install_as_xsub(xstcc_symbol *self, char *full_subname = NULL)
  PREINIT:
    XSUBADDR_t sub;
  CODE:
    sub = (XSUBADDR_t)self;
    RETVAL = newXS(full_subname, sub, "anon");
    sv_2mortal((SV *)RETVAL);
  OUTPUT: RETVAL

MODULE = XS::TCC        PACKAGE = XS::TCC
