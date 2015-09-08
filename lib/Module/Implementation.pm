#line 1 "Module/Implementation.pm"
package Module::Implementation;
{
  $Module::Implementation::VERSION = '0.07';
}
BEGIN {
  $Module::Implementation::AUTHORITY = 'cpan:DROLSKY';
}

use strict;
use warnings;

use Module::Runtime 0.012 qw( require_module );
use Try::Tiny;

my %Implementation;

sub build_loader_sub {
    my $caller = caller();

    return _build_loader( $caller, @_ );
}

sub _build_loader {
    my $package = shift;
    my %args    = @_;

    my @implementations = @{ $args{implementations} };
    my @symbols = @{ $args{symbols} || [] };

    my $implementation;
    my $env_var = uc $package;
    $env_var =~ s/::/_/g;
    $env_var .= '_IMPLEMENTATION';

    return sub {
        my ( $implementation, $loaded ) = _load_implementation(
            $package,
            $ENV{$env_var},
            \@implementations,
        );

        $Implementation{$package} = $implementation;

        _copy_symbols( $loaded, $package, \@symbols );

        return $loaded;
    };
}

sub implementation_for {
    my $package = shift;

    return $Implementation{$package};
}

sub _load_implementation {
    my $package         = shift;
    my $env_value       = shift;
    my $implementations = shift;

    if ($env_value) {
        die "$env_value is not a valid implementation for $package"
            unless grep { $_ eq $env_value } @{$implementations};

        my $requested = "${package}::$env_value";

        # Values from the %ENV hash are tainted. We know it's safe to untaint
        # this value because the value was one of our known implementations.
        ($requested) = $requested =~ /^(.+)$/;

        try {
            require_module($requested);
        }
        catch {
            require Carp;
            Carp::croak("Could not load $requested: $_");
        };

        return ( $env_value, $requested );
    }
    else {
        my $err;
        for my $possible ( @{$implementations} ) {
            my $try = "${package}::$possible";

            my $ok;
            try {
                require_module($try);
                $ok = 1;
            }
            catch {
                $err .= $_ if defined $_;
            };

            return ( $possible, $try ) if $ok;
        }

        require Carp;
        if ( defined $err && length $err ) {
            Carp::croak(
                "Could not find a suitable $package implementation: $err");
        }
        else {
            Carp::croak(
                'Module::Runtime failed to load a module but did not throw a real error. This should never happen. Something is very broken'
            );
        }
    }
}

sub _copy_symbols {
    my $from_package = shift;
    my $to_package   = shift;
    my $symbols      = shift;

    for my $sym ( @{$symbols} ) {
        my $type = $sym =~ s/^([\$\@\%\&\*])// ? $1 : '&';

        my $from = "${from_package}::$sym";
        my $to   = "${to_package}::$sym";

        {
            no strict 'refs';
            no warnings 'once';

            # Copied from Exporter
            *{$to}
                = $type eq '&' ? \&{$from}
                : $type eq '$' ? \${$from}
                : $type eq '@' ? \@{$from}
                : $type eq '%' ? \%{$from}
                : $type eq '*' ? *{$from}
                : die
                "Can't copy symbol from $from_package to $to_package: $type$sym";
        }
    }
}

1;

# ABSTRACT: Loads one of several alternate underlying implementations for a module

__END__

#line 284
