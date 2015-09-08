#line 1 "Params/Validate.pm"
package Params::Validate;
$Params::Validate::VERSION = '1.10';
use 5.008001;

use strict;
use warnings;

use Exporter;
use Module::Implementation;
use Params::Validate::Constants;

use vars qw( $NO_VALIDATION %OPTIONS $options );

our @ISA = 'Exporter';

my %tags = (
    types => [
        qw(
            SCALAR
            ARRAYREF
            HASHREF
            CODEREF
            GLOB
            GLOBREF
            SCALARREF
            HANDLE
            BOOLEAN
            UNDEF
            OBJECT
            )
    ],
);

our %EXPORT_TAGS = (
    'all' => [
        qw( validate validate_pos validation_options validate_with ),
        map { @{ $tags{$_} } } keys %tags
    ],
    %tags,
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} }, 'set_options' );
our @EXPORT = qw( validate validate_pos );

$NO_VALIDATION = $ENV{PERL_NO_VALIDATION};

{
    my $loader = Module::Implementation::build_loader_sub(
        implementations => [ 'XS', 'PP' ],
        symbols         => [
            qw(
                validate
                validate_pos
                validate_with
                validation_options
                set_options
                ),
        ],
    );

    $ENV{PARAMS_VALIDATE_IMPLEMENTATION} = 'PP' if $ENV{PV_TEST_PERL};

    $loader->();
}

1;

# ABSTRACT: Validate method/function parameters

__END__

#line 845
