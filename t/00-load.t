#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'AnyEvent::DataStream' ) || print "Bail out!\n";
}

diag( "Testing AnyEvent::DataStream $AnyEvent::DataStream::VERSION, Perl $], $^X" );
