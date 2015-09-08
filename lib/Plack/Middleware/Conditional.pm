#line 1 "Plack/Middleware/Conditional.pm"
package Plack::Middleware::Conditional;
use strict;
use parent qw(Plack::Middleware);

use Plack::Util::Accessor qw( condition middleware builder );

sub prepare_app {
    my $self = shift;
    $self->middleware( $self->builder->($self->app) );
}

sub call {
    my($self, $env) = @_;

    my $app = $self->condition->($env) ? $self->middleware : $self->app;
    return $app->($env);
}

1;

__END__

#line 87
