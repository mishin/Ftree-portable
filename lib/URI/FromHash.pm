#line 1 "URI/FromHash.pm"
package URI::FromHash;
{
  $URI::FromHash::VERSION = '0.04';
}
BEGIN {
  $URI::FromHash::AUTHORITY = 'cpan:DROLSKY';
}

use strict;
use warnings;

use Params::Validate qw( validate SCALAR ARRAYREF HASHREF );
use URI;
use URI::QueryParam;

use Exporter qw( import );

our @EXPORT_OK = qw( uri uri_object );

my %BaseParams = (
    scheme   => { type => SCALAR,            optional => 1 },
    username => { type => SCALAR,            optional => 1 },
    password => { type => SCALAR,            default  => '' },
    host     => { type => SCALAR,            optional => 1 },
    port     => { type => SCALAR,            optional => 1 },
    path     => { type => SCALAR | ARRAYREF, optional => 1 },
    query    => { type => HASHREF,           default  => {} },
    fragment => { type => SCALAR,            optional => 1 },
);

sub uri_object {
    my %p = validate( @_, \%BaseParams );
    _check_required( \%p );

    my $uri = URI->new();

    $uri->scheme( $p{scheme} )
        if grep { defined && length } $p{scheme};

    if ( grep { defined && length } $p{username}, $p{password} ) {
        $p{username} ||= '';
        $p{password} ||= '';
        if ( $uri->can('user') && $uri->can('password') ) {
            $uri->user( $p{username} );
            $uri->password( $p{password} );
        }
        else {
            $uri->userinfo("$p{username}:$p{password}");
        }
    }

    for my $k (qw( host port )) {
        $uri->$k( $p{$k} )
            if grep { defined && length } $p{$k};
    }

    if ( $p{path} ) {
        if ( ref $p{path} ) {
            $uri->path( join '/', grep { defined } @{ $p{path} } );
        }
        else {
            $uri->path( $p{path} );
        }
    }

    while ( my ( $k, $v ) = each %{ $p{query} } ) {
        $uri->query_param( $k => $v );
    }

    $uri->fragment( $p{fragment} )
        if grep { defined && length } $p{fragment};

    return $uri;
}

{
    my $spec = {
        %BaseParams,
        query_separator => { type => SCALAR, default => ';' },
    };

    sub uri {
        my %p = validate(
            @_,
            $spec,
        );
        _check_required( \%p );

        my $sep = delete $p{query_separator};
        my $uri = uri_object(%p);

        if ( $sep ne '&' && $uri->query() ) {
            my $query = $uri->query();
            $query =~ s/&/$sep/g;
            $uri->query($query);
        }

        # force stringification
        return $uri->canonical() . '';
    }
}

sub _check_required {
    my $p = shift;

    return
        if (
        grep { defined and length }
        map { $p->{$_} } qw( host fragment )
        );

    return
        if ref $p->{path}
        ? @{ $p->{path} }
        : defined $p->{path} && length $p->{path};

    return if keys %{ $p->{query} };

    require Carp;
    local $Carp::CarpLevel = 1;
    Carp::croak( 'None of the required parameters '
            . '(host, path, fragment, or query) were given' );
}

1;

# ABSTRACT: Build a URI from a set of named parameters

__END__

#line 249
