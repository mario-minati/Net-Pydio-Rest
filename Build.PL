use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Net::Pydio::Rest',
    license             => 'perl_5',
    dist_author         => q{Mario Minati <cpan@minati.de>},
    dist_version_from   => 'lib/Net/Pydio/Rest.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        #'ABC'              => 1.6,
        #'Foo::Bar::Module' => 5.0401,
    },
    add_to_cleanup     => [ 'Net-Pydio-Rest-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
