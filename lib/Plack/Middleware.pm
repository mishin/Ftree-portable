#line 1 "Plack/Middleware.pm"
package Plack::Middleware;
use strict;
use warnings;
use Carp ();
use parent qw(Plack::Component);
use Plack::Util;
use Plack::Util::Accessor qw( app );

sub wrap {
    my($self, $app, @args) = @_;
    if (ref $self) {
        $self->{app} = $app;
    } else {
        $self = $self->new({ app => $app, @args });
    }
    return $self->to_app;
}

1;

__END__

#line 192
