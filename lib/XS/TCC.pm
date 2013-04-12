package XS::TCC;
use 5.10.1;
use strict;
use warnings;

our $VERSION = '0.01';

use Carp ();
use Exporter 'import';
use XSLoader;

use ExtUtils::Embed ();
use ExtUtils::Typemaps;
use File::Spec;

use XS::TCC::Parser;

XSLoader::load('XS::TCC', $VERSION);

our @EXPORT_OK = qw(
  tcc_inline
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

our $CCOPTS = ExtUtils::Embed::ccopts;

my $CodeHeader = <<'HERE';
#define PERL_NO_GET_CONTEXT

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

/* The XS_EXTERNAL macro is used for functions that must not be static
 * like the boot XSUB of a module. If perl didn't have an XS_EXTERNAL
 * macro defined, the best we can do is assume XS is the same.
 * Dito for XS_INTERNAL.
 */
#ifndef XS_EXTERNAL
#  define XS_EXTERNAL(name) XS(name)
#endif
#ifndef XS_INTERNAL
#  define XS_INTERNAL(name) XS(name)
#endif

#ifndef PERL_UNUSED_VAR
#  define PERL_UNUSED_VAR(var) if (0) var = var
#endif

#ifndef dVAR
#  define dVAR		dNOOP
#endif


#ifndef PERL_ARGS_ASSERT_CROAK_XS_USAGE
#define PERL_ARGS_ASSERT_CROAK_XS_USAGE assert(cv); assert(params)

/* prototype to pass -Wmissing-prototypes */
STATIC void
S_croak_xs_usage(pTHX_ const CV *const cv, const char *const params);

STATIC void
S_croak_xs_usage(pTHX_ const CV *const cv, const char *const params)
{
    const GV *const gv = CvGV(cv);

    PERL_ARGS_ASSERT_CROAK_XS_USAGE;

    if (gv) {
        const char *const gvname = GvNAME(gv);
        const HV *const stash = GvSTASH(gv);
        const char *const hvname = stash ? HvNAME(stash) : NULL;

        if (hvname)
            Perl_croak(aTHX_ "Usage: %s::%s(%s)", hvname, gvname, params);
        else
            Perl_croak(aTHX_ "Usage: %s(%s)", gvname, params);
    } else {
        /* Pants. I don't think that it should be possible to get here. */
        Perl_croak(aTHX_ "Usage: CODE(0x%"UVxf")(%s)", PTR2UV(cv), params);
    }
}
#undef  PERL_ARGS_ASSERT_CROAK_XS_USAGE

#ifdef PERL_IMPLICIT_CONTEXT
#  define croak_xs_usage(a,b)    S_croak_xs_usage(aTHX_ a,b)
#else
#  define croak_xs_usage        S_croak_xs_usage
#endif

#endif
HERE


SCOPE: {
  my $compiler;
  sub _get_compiler {
    return $compiler if $compiler;
    $compiler = XS::TCC::TCCState->new;
    return $compiler;
  } # end _get_compiler
} # end SCOPE


SCOPE: {
  my $core_typemap;
  sub _get_core_typemap {
    return $core_typemap if $core_typemap;

    my @tm;
    foreach my $dir (@INC) {
      my $file = File::Spec->catfile($dir, ExtUtils => 'typemap');
      unshift @tm, $file if -e $file;
    }

    $core_typemap = ExtUtils::Typemaps->new();
    foreach my $typemap_loc (@tm) {
      next unless -f $typemap_loc;
      # skip directories, binary files etc.
      warn("Warning: ignoring non-text typemap file '$typemap_loc'\n"), next
        unless -T $typemap_loc;

      $core_typemap->merge(file => $typemap_loc, replace => 1);
    }

    return $core_typemap;
  } # end _get_core_typemap
} # end SCOPE


sub tcc_inline (@) {
  my $code;

  $code = pop @_ if @_ % 2;
  my %args = @_;

  if (defined $code and defined $args{code}) {
    Carp::croak("Can't specify code both as a named and as a positional parameter");
  }
  $code //= $args{code};
  Carp::croak("Need code to compile") if not defined $code;

  my $package = $args{package} // (caller())[0];

  # Set up the typemap object if any (defaulting to core typemaps)
  my $typemap;
  my $typemap_arg = $args{typemap};
  if (not defined($typemap_arg)) {
    $typemap = _get_core_typemap();
  }
  elsif (ref($typemap_arg)) {
    $typemap = _get_core_typemap()->clone(shallow => 1);
    $typemap->merge(typemap => $typemap_arg);
  }
  else {
    $typemap = _get_core_typemap()->clone(shallow => 1);
    $typemap->add_string(string => $typemap_arg);
  }

  # Function signature parsing
  my $parse_result = XS::TCC::Parser::extract_function_metadata($code);
  return
    if not $parse_result
    or not @{$parse_result->{function_names}};

  # FIXME code to eval the typemaps for the function sig
  my @code = ($CodeHeader, $code);
  foreach my $cfun_name (@{$parse_result->{function_names}}) {
    my $fun_info = $parse_result->{functions}{$cfun_name};
    _gen_single_function_xs_wrapper($cfun_name, $fun_info, \@code);
  }

  my $final_code = join "\n", @code;
  #warn $final_code;
  my $compiler = _get_compiler();

  # Code to catch compile errors
  my $errmsg;
  my $err_hook = sub { $errmsg = $_[0] };

  $compiler->set_error_callback($err_hook);

  # Do the compilation
  $compiler->set_options($args{ccopts} // $CCOPTS);
  $compiler->compile_string($final_code);
  $compiler->relocate();

  if (defined $errmsg) {
    $errmsg = _build_compile_error_msg($errmsg, 1);
    Carp::croak($errmsg);
  }

  # FIXME code to install the XSUB
  # for (functions) {
  #   my $sym = $compiler->get_symbol($xs_function_name);
  #   $sym->install_as_xsub($package . "::" . $xs_function_name);
  # }
}


sub _build_compile_error_msg {
  my ($msg, $caller_level) = @_;
  $caller_level++;
  # TODO write code to emit file/line info
  return $msg;
}

sub _gen_single_function_xs_wrapper {
  my ($cfun_name, $fun_info, $code_ary) = @_;

  my $arg_names = $fun_info->{arg_names};
  my $nparams = scalar(@$arg_names);
  my $arg_names_str = join ", ", map {s/\W/_/; $_} @$arg_names;

  push @$code_ary, <<FUN_HEADER;
XS_EXTERNAL(XS_$cfun_name); /* prototype to pass -Wmissing-prototypes */
XS_EXTERNAL(XS_$cfun_name)
{
  dVAR; dXSARGS;
  if (items != $nparams)
    croak_xs_usage(cv,  "$arg_names_str");
  PERL_UNUSED_VAR(ax); /* -Wall */
  SP -= items;
  {
FUN_HEADER

  # FIXME emit input typemaps
  # FIXME emit function call
  # FIXME emit output typemaps

  push @$code_ary, <<FUN_FOOTER;
  }
  XRETURN(1);
}
FUN_FOOTER

  return();
}

1;

__END__

=head1 NAME

XS::TCC - blah blah blah

=head1 SYNOPSIS


=head1 DESCRIPTION

=head1 SEE ALSO

=over

=item * L<C::TCC>

=item * L<Inline> and L<Inline::C>

=item * L<ExtUtils::ParseXS> and L<ExtUtils::Typemaps>

=back

=head1 AUTHOR

Steffen Mueller E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
