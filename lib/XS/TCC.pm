package XS::TCC;
use 5.10.1;
use strict;
use warnings;

our $VERSION = '0.02';

use constant {
  TCC_OUTPUT_MEMORY     => 0,
  TCC_OUTPUT_EXE        => 1,
  TCC_OUTPUT_DLL        => 2,
  TCC_OUTPUT_OBJ        => 3,
  TCC_OUTPUT_PREPROCESS => 4,
};

use Carp ();
use Exporter 'import';
use XSLoader;

use ExtUtils::Embed ();
use ExtUtils::Typemaps;
use ExtUtils::ParseXS::Eval;
use File::Spec;
use File::ShareDir;

our $RuntimeIncludeDir = File::ShareDir::dist_dir('XS-TCC');

use XS::TCC::Typemaps;
use XS::TCC::Parser;

XSLoader::load('XS::TCC', $VERSION);

our @EXPORT_OK = qw(
  tcc_inline
  TCC_OUTPUT_MEMORY
  TCC_OUTPUT_EXE
  TCC_OUTPUT_DLL
  TCC_OUTPUT_OBJ
  TCC_OUTPUT_PREPROCESS
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

our $CCOPTS = ExtUtils::Embed::ccopts;

my $CodeHeader = <<'HERE';
#ifndef XS_TCC_INIT
#define XS_TCC_INIT
/* #define PERL_NO_GET_CONTEXT */

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include <typemap_func.h>

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

#endif /* XS_TCC_INIT */
HERE


SCOPE: {
  my @compilers; # never die...
  #my $compiler;
  sub _get_compiler {
    #return $compiler if $compiler;
    my $compiler = XS::TCC::TCCState->new;
    $compiler->set_lib_path($RuntimeIncludeDir);
    $compiler->add_sysinclude_path($RuntimeIncludeDir);
    #push @compilers, $compiler;
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

    # Override core typemaps with custom function-based replacements.
    # This is because GCC compiled functions are likely faster than inlined code in TCC.
    $core_typemap->merge(replace => 1, typemap => $XS::TCC::Typemaps::Typemap);

    return $core_typemap;
  } # end _get_core_typemap
} # end SCOPE



# current options:
# code, warn_code, package, typemap, add_files, ccopts
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

  # eval the typemaps for the function sig
  my @code = ($CodeHeader, $code);
  foreach my $cfun_name (@{$parse_result->{function_names}}) {
    my $fun_info = $parse_result->{functions}{$cfun_name};
    my $xs_fun = _gen_single_function_xs_wrapper($package, $cfun_name, $fun_info, $typemap, \@code);
    $fun_info->{xs_function_name} = $xs_fun;
  }

  my $final_code = join "\n", @code;

  warn _add_line_nums($final_code) if $args{warn_code};

  my $compiler = _get_compiler();

  # Code to catch compile errors
  my $errmsg;
  my $err_hook = sub { $errmsg = $_[0] };

  $compiler->set_error_callback($err_hook);

  # Add user-specified files
  my @add_files;
  @add_files = ref($args{add_files}) ? @{$args{add_files}} : $args{add_files}
    if defined $args{add_files};
  $compiler->add_file($_) for @add_files;

  # Do the compilation
  $compiler->set_options(($args{ccopts} // $CCOPTS));
  $compiler->compile_string($final_code);
  $compiler->relocate();

  if (defined $errmsg) {
    $errmsg = _build_compile_error_msg($errmsg, 1);
    Carp::croak($errmsg);
  }

  # install the XSUBs
  foreach my $cfun_name (@{$parse_result->{function_names}}) {
    my $fun_info = $parse_result->{functions}{$cfun_name};
    my $sym = $compiler->get_symbol($fun_info->{xs_function_name});
    my $perl_name = $package . "::" . $cfun_name;
    my $sub = $sym->as_xsub();
    no strict 'refs';
    *{"$perl_name"} = $sub;
  }

}


sub _build_compile_error_msg {
  my ($msg, $caller_level) = @_;
  $caller_level++;
  # TODO write code to emit file/line info
  return $msg;
}

sub _gen_single_function_xs_wrapper {
  my ($package, $cfun_name, $fun_info, $typemap, $code_ary) = @_;

  my $arg_names = $fun_info->{arg_names};
  my $nparams = scalar(@$arg_names);
  my $arg_names_str = join ", ", map {s/\W/_/; $_} @$arg_names;

  # Return type and output typemap preparation
  my $ret_type = $fun_info->{return_type};
  my $is_void_function = $ret_type eq 'void';
  my $retval_decl = $is_void_function ? '' : "$ret_type RETVAL;";

  my $out_typemap;
  my $outputmap;
  my $dxstarg = "";
  if (not $is_void_function) {
    $out_typemap = $typemap->get_typemap(ctype => $ret_type);
    $outputmap = $out_typemap
                 ? $typemap->get_outputmap(xstype => $out_typemap->xstype)
                 : undef;
    Carp::croak("No output typemap found for return type '$ret_type'")
      if not $outputmap;
    # TODO implement TARG optimization below
    #$dxstarg = $outputmap->targetable ? " dXSTARG;" : "";
  }

  # Emit function header and declarations
  (my $xs_pkg_name = $package) =~ s/:+/_/g;
  my $xs_fun_name = "XS_${xs_pkg_name}_$cfun_name";
  push @$code_ary, <<FUN_HEADER;
XS_EXTERNAL($xs_fun_name); /* prototype to pass -Wmissing-prototypes */
XS_EXTERNAL($xs_fun_name)
{
  dVAR; dXSARGS;$dxstarg
  if (items != $nparams)
    croak_xs_usage(cv,  "$arg_names_str");
  /* PERL_UNUSED_VAR(ax); */ /* -Wall */
  /* SP -= items; */
  {
    $retval_decl


FUN_HEADER

  my $do_pass_threading_context = $fun_info->{need_threading_context};

  # emit input typemaps
  my @input_decl;
  my @input_assign;
  for my $argno (0..$#{$fun_info->{arg_names}}) {
    my $aname = $fun_info->{arg_names}[$argno];
    my $atype = $fun_info->{arg_types}[$argno];
    (my $decl_type = $atype) =~ s/^\s*const\b\s*//;

    my $tm = $typemap->get_typemap(ctype => $atype);
    my $im = !$tm ? undef : $typemap->get_inputmap(xstype => $tm->xstype);

    Carp::croak("No input typemap found for type '$atype'")
      if not $im;
    my $imcode = $im->cleaned_code;

    my $vars = {
      Package => $package,
      ALIAS => $cfun_name,
      func_name => $cfun_name,
      Full_func_name => $cfun_name,
      pname => $package . "::" . $cfun_name,
      type => $decl_type,
      ntype => $decl_type,
      arg => "ST($argno)",
      var => $aname,
      init => undef,
      # FIXME some of these are guesses at their true meaning. Validate in EU::PXS
      num => $argno,
      printed_name => $aname,
      argoff => $argno,
    };

    # FIXME do we want to support the obscure ARRAY/Ptr logic (subtype, ntype)?
    my $out = ExtUtils::ParseXS::Eval::eval_input_typemap_code(
      $vars, qq{"$imcode"}, $vars
    );

    $out =~ s/;\s*$//;
    if ($out =~ /^\s*\Q$aname\E\s*=/) {
      push @input_decl, "    $decl_type $out;";
    }
    else {
      push @input_decl, "    $decl_type $aname;";
      push @input_assign, "    $out;";
    }
  }
  push @$code_ary, @input_decl, @input_assign;

  # emit function call
  my $fun_call_assignment = $is_void_function ? "" : "RETVAL = ";
  my $arglist = join ", ",  @{ $fun_info->{arg_names} };
  my $threading_context = "";
  if ($do_pass_threading_context) {
     $threading_context = scalar(@{ $fun_info->{arg_names} }) == 0
                          ? "aTHX " : "aTHX_ ";
  }
  push @$code_ary, "    ${fun_call_assignment}$cfun_name($threading_context$arglist);\n";

  # emit output typemap
  if (not $is_void_function) {
    my $omcode = $outputmap->cleaned_code;
    my $vars = {
      Package => $package,
      ALIAS => $cfun_name,
      func_name => $cfun_name,
      Full_func_name => $cfun_name,
      pname => $package . "::" . $cfun_name,
      type => $ret_type,
      ntype => $ret_type,
      arg => "ST(0)",
      var => "RETVAL",
    };

    # FIXME do we want to support the obscure ARRAY/Ptr logic (subtype, ntype)?

    # TODO TARG ($om->targetable) optimization!
    my $out = ExtUtils::ParseXS::Eval::eval_output_typemap_code(
      $vars, qq{"$omcode"}, $vars
    );
    push @$code_ary, "    ST(0) = sv_newmortal();";
    push @$code_ary, "    " . $out;
  }


  my $nreturnvalues = $is_void_function ? 0 : 1;
  push @$code_ary, <<FUN_FOOTER;
  }
  XSRETURN($nreturnvalues);
}
FUN_FOOTER

  return($xs_fun_name);
}

# just for debugging
sub _add_line_nums {
  my $code = shift;
  my $i = shift || 1;
  my @l = split /\n/, $code;
  my $n = @l + $i - 1;
  my $len = length($n);
  return join("\n", map sprintf("% ${len}u: %s", $i++, $_), @l);
}

1;

__END__

=head1 NAME

XS::TCC - Embed, wrap & compile C code in Perl without going to disk

=head1 SYNOPSIS

  # WARNING interface is bound to change...
  use XS::TCC qw(tcc_inline);
  
  tcc_inline q{
    int foo(int bar) {
      return bar * 2;
    }
  };
  
  print foo(3.1), "\n"; # prints 6.2
  # more elaborate functions involving Perl types work as well

=head1 DESCRIPTION

B<This is a highly experimental module. Use at your own risk. Get in
touch with the author(s) if in doubt.>

C<XS::TCC> allows you to embed C code into your Perl that is compiled
and linked on the fly, in memory, without ever touching your disk
except to read the Perl code in the first place. This amazing feat
actually has very little to do with this module's code but rather
with TCC (TinyCC, see tinycc.org) which allows compilation and linking
in memory.

On my first-gen core i5 laptop, making two small-medium size functions
available to Perl takes around 30ms including parse, wrapper code generation,
typemapping, compilation, linking, and XSUB installation. Wrapping more code
is bound to be relatively faster.

The output of TCC is slower than the equivalent function compiled with GCC,
but both beat regular Perl by a wide margin {citation required}.

=head1 SEE ALSO

=over

=item * L<C::TCC>

=item * L<Inline> and L<Inline::C>

=item * L<ExtUtils::ParseXS> and L<ExtUtils::Typemaps>

=back

=head1 AUTHOR

Steffen Mueller E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This package includes a copy of the TCC sources. The TCC sources are

Copyright (C) Fabrice Bellard.

  TCC is distributed under the GNU Lesser General Public License
  (see COPYING file).

The rest of the code is

Copyright (C) 2013 by Steffen Mueller

  XS::TCC is distributed under the GNU Lesser General Public License
  (see COPYING file).

=cut
