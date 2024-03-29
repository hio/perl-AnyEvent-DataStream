use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'AnyEvent::DataStream',
    AUTHOR           => q{YAMASHINA Hio <hio@hio.jp>},
    VERSION_FROM     => 'lib/AnyEvent/DataStream.pm',
    ABSTRACT_FROM    => 'lib/AnyEvent/DataStream.pm',
    LICENSE          => 'Perl',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'AnyEvent' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'AnyEvent-DataStream-*' },
);
