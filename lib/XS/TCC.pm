package XS::TCC;
use 5.10.1;
use strict;
use warnings;

our $VERSION = '0.01';

use Carp qw/croak/;
use Exporter 'import';
use XSLoader;

use ExtUtils::Typemaps;
use File::Spec;

use XS::TCC::Parser;

XSLoader::load('XS::TCC', $VERSION);

our @EXPORT_OK = qw(
  tcc_inline
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);


my $CodeHeader = <<'HERE';
#define PERL_NO_GET_CONTEXT

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#include <ppport.h>
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
  my %args;
  if (@_ % 2) {
    $code = pop @_;
  }
  %args = @_;
  if (defined $code and exists $args{code}) {
    croak("Can't specify code both as a named and as a positional parameter");
  }
  $code //= $args{code};
  croak("Need code to compile") if not defined $code;

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

  # FIXME code to do the function signature parsing
  # FIXME code to eval the typemaps for the function sig
  # FIXME code to do the compilation
  # FIXME code to install the XSUB
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
