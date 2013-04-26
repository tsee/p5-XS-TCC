use 5.008;

use strict;
use warnings;

use ExtUtils::MakeMaker;
use Config qw(%Config);
use Getopt::Long qw(GetOptions);
use Cwd qw(cwd);
use File::Basename qw(fileparse);

my $debug = $ENV{DEBUG};
my $tcc_static_lib_location = '';
my $tcc_include_location = '';
my $tcc_source_location = 'tcc-0.9.26';

GetOptions(
    'debug|d' => \$debug,
    'tcc_static_lib_location=s' => \$tcc_static_lib_location,
    'tcc_include_location=s' => \$tcc_include_location,
);

my $do_build_tcc = $tcc_static_lib_location eq '' ? 1 : 0;
$tcc_include_location = File::Spec->catdir($tcc_source_location)
    if $tcc_include_location eq '';
$tcc_static_lib_location = File::Spec->catfile($tcc_source_location, 'libtcc' . $Config{lib_ext})
    if $tcc_static_lib_location eq '';


our $OPTIMIZE;

if ($Config{gccversion}) {
    $OPTIMIZE = '-O3 -Wall -W';
} elsif ($Config{osname} eq 'MSWin32') {
    $OPTIMIZE = '-O2 -W4';
} else {
    $OPTIMIZE = $Config{optimize};
}

if ($debug) {
    $OPTIMIZE .= ' -g';
}

my @tcc_runtime_files;
if ($do_build_tcc) {
    @tcc_runtime_files = glob(File::Spec->catfile($tcc_source_location, "include", "*"));
    push @tcc_runtime_files, File::Spec->catfile($tcc_source_location, "libtcc1$Config{lib_ext}");
}
else {
    @tcc_runtime_files = glob(File::Spec->catfile($tcc_include_location, "*"));
    push @tcc_runtime_files, File::Spec->catfile($tcc_static_lib_location, "libtcc1$Config{lib_ext}");
}
push @tcc_runtime_files, 'typemap_func.h';

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile1(
    MIN_PERL_VERSION => '5.008',
    META_MERGE => {
        resources => {
            repository => 'git://github.com/tsee/p5-XS-TCC.git'
        },
    },
    BUILD_REQUIRES => {
        'Test::More' => '0.88',
    },
    NAME              => 'XS::TCC',
    VERSION_FROM      => 'lib/XS/TCC.pm', # finds $VERSION
    PREREQ_PM         => {
        'XSLoader' => 0,
        'ExtUtils::Typemaps' => '0.18_01',
        'ExtUtils::Embed' => 0,
        'File::Spec' => 0,
        'File::ShareDir' => 0,
    },
    LICENSE => 'perl',
    ABSTRACT_FROM => 'lib/XS/TCC.pm',
    AUTHOR => 'Steffen Mueller <smueller@cpan.org>',
    #LIBS              => ['-Ltcc-install/lib', '-ltcc'], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I. -I' . $tcc_include_location,
    OPTIMIZE          => $OPTIMIZE,
    # Un-comment this if you add C files to link with later:
    OBJECT            => '$(O_FILES)', # link all the C files too
    META_MERGE => {
        configure_requires => {
            'Getopt::Long' => 0,
            'Cwd' => 0,
            'File::Spec' => 0,
            'File::Basename' => 0,
        },
    },
    ($do_build_tcc ? (MYEXTLIB => $tcc_static_lib_location) : ()),
);

sub MY::postamble {
    my $self = shift;
    my @ret;
    if ($do_build_tcc) {
        my $extra = join " ", $Config{ccflags}, $Config{cccdlflags};
        push @ret, <<HERE;
\$(MYEXTLIB):
	cd $tcc_source_location && \$(SHELL) ./configure --extra-cflags='$extra' && \$(MAKE)

clean ::
	cd $tcc_source_location && \$(MAKE) clean && \$(RM) config.h config.mak

HERE
    }
    push @ret, <<HERE;

subdirs ::
	\$(NOECHO) \$(ABSPERLRUN) -MExtUtils::Install -e 'pm_to_blib({\@ARGV}, '\\''\$(INST_LIB)'\\'')' -- \\
HERE
        foreach my $if (0..$#tcc_runtime_files) {
            my $f = $tcc_runtime_files[$if];
            my $name = fileparse($f);
            push @ret, "\t  $f \$(INST_LIB)/auto/share/dist/\$(DISTNAME)/$name"
              . ($if != $#tcc_runtime_files ? " \\\n" : "\n");
        }
        push @ret, "\n";
    return join "", @ret;
}


sub WriteMakefile1 {  #Written by Alexandr Ciornii, version 0.20. Added by eumm-upgrade.
    my %params=@_;
    my $eumm_version=$ExtUtils::MakeMaker::VERSION;
    $eumm_version=eval $eumm_version;
    die "EXTRA_META is deprecated" if exists $params{EXTRA_META};
    die "License not specified" if not exists $params{LICENSE};
    if ($params{BUILD_REQUIRES} and $eumm_version < 6.5503) {
        #EUMM 6.5502 has problems with BUILD_REQUIRES
        $params{PREREQ_PM}={ %{$params{PREREQ_PM} || {}} , %{$params{BUILD_REQUIRES}} };
        delete $params{BUILD_REQUIRES};
    }
    delete $params{CONFIGURE_REQUIRES} if $eumm_version < 6.52;
    delete $params{MIN_PERL_VERSION} if $eumm_version < 6.48;
    delete $params{META_MERGE} if $eumm_version < 6.46;
    delete $params{META_ADD} if $eumm_version < 6.46;
    delete $params{LICENSE} if $eumm_version < 6.31;
    delete $params{AUTHOR} if $] < 5.005;
    delete $params{ABSTRACT_FROM} if $] < 5.005;
    delete $params{BINARY_LOCATION} if $] < 5.005;

    WriteMakefile(%params);
}

