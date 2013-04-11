package XS::TCC;
use 5.008;
use strict;
use warnings;
use Carp qw/croak/;
use XSLoader;

our $VERSION = '0.01';

use XS::TCC::Parser;
use Exporter 'import';

XSLoader::load('XS::TCC', $VERSION);

our @EXPORT_OK = qw(
  tcc_inline
);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

my $CodeHeader = <<'HERE';
#include <stdlib.h>

HERE

sub tcc_inline {
  my $code;
  my %args;
  if (@_ % 2) {
    $code = pop @_;
  }
  %args = @_;
  if (defined $code and exists $args{code}) {
    croak("Can't specify code both as a named and as a positional parameter");
  }
  $code = $args{code} if not defined $code;
  croak("Need code to compile") if not defined $code;

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
