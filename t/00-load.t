#!perl -T
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Net::Pydio::Rest' ) || print "Bail out!\n";
}

diag( "Testing Net::Pydio::Rest $Net::Pydio::Rest::VERSION, Perl $], $^X" );
