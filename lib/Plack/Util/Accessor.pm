#line 1 "Plack/Util/Accessor.pm"
package Plack::Util::Accessor;
use strict;
use warnings;

sub import {
    shift;
    return unless @_;
    my $package = caller();
    mk_accessors( $package, @_ );
}

sub mk_accessors {
    my $package = shift;
    no strict 'refs';
    foreach my $field ( @_ ) {
        *{ $package . '::' . $field } = sub {
            return $_[0]->{ $field } if scalar( @_ ) == 1;
            return $_[0]->{ $field }  = scalar( @_ ) == 2 ? $_[1] : [ @_[1..$#_] ];
        };
    }
}

1;

__END__

#line 47
