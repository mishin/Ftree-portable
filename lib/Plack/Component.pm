#line 1 "Plack/Component.pm"
package Plack::Component;
use strict;
use warnings;
use Carp ();
use Plack::Util;
use overload '&{}' => \&to_app_auto, fallback => 1;

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self;
    if (@_ == 1 && ref $_[0] eq 'HASH') {
        $self = bless {%{$_[0]}}, $class;
    } else {
        $self = bless {@_}, $class;
    }

    $self;
}

sub to_app_auto {
    my $self = shift;
    if (($ENV{PLACK_ENV} || '') eq 'development') {
        my $class = ref($self);
        warn "WARNING: Automatically converting $class instance to a PSGI code reference. " .
          "If you see this warning for each request, you probably need to explicitly call " .
          "to_app() i.e. $class->new(...)->to_app in your PSGI file.\n";
    }
    $self->to_app(@_);
}

# NOTE:
# this is for back-compat only,
# future modules should use
# Plack::Util::Accessor directly
# or their own favorite accessor
# generator.
# - SL
sub mk_accessors {
    my $self = shift;
    Plack::Util::Accessor::mk_accessors( ref( $self ) || $self, @_ )
}

sub prepare_app { return }

sub to_app {
    my $self = shift;
    $self->prepare_app;
    return sub { $self->call(@_) };
}


sub response_cb {
    my($self, $res, $cb) = @_;
    Plack::Util::response_cb($res, $cb);
}

1;

__END__

#line 163
