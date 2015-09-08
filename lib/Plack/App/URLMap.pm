#line 1 "Plack/App/URLMap.pm"
package Plack::App::URLMap;
use strict;
use warnings;
use parent qw(Plack::Component);
use constant DEBUG => $ENV{PLACK_URLMAP_DEBUG};

use Carp ();

sub mount { shift->map(@_) }

sub map {
    my $self = shift;
    my($location, $app) = @_;

    my $host;
    if ($location =~ m!^https?://(.*?)(/.*)!) {
        $host     = $1;
        $location = $2;
    }

    if ($location !~ m!^/!) {
        Carp::croak("Paths need to start with /");
    }
    $location =~ s!/$!!;

    push @{$self->{_mapping}}, [ $host, $location, qr/^\Q$location\E/, $app ];
}

sub prepare_app {
    my $self = shift;
    # sort by path length
    $self->{_sorted_mapping} = [
        map  { [ @{$_}[2..5] ] }
        sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] }
        map  { [ ($_->[0] ? length $_->[0] : 0), length($_->[1]), @$_ ] } @{$self->{_mapping}},
    ];
}

sub call {
    my ($self, $env) = @_;

    my $path_info   = $env->{PATH_INFO};
    my $script_name = $env->{SCRIPT_NAME};

    my($http_host, $server_name) = @{$env}{qw( HTTP_HOST SERVER_NAME )};

    if ($http_host and my $port = $env->{SERVER_PORT}) {
        $http_host =~ s/:$port$//;
    }

    for my $map (@{ $self->{_sorted_mapping} }) {
        my($host, $location, $location_re, $app) = @$map;
        my $path = $path_info; # copy
        no warnings 'uninitialized';
        DEBUG && warn "Matching request (Host=$http_host Path=$path) and the map (Host=$host Path=$location)\n";
        next unless not defined $host     or
                    $http_host   eq $host or
                    $server_name eq $host;
        next unless $location eq '' or $path =~ s!$location_re!!;
        next unless $path eq '' or $path =~ m!^/!;
        DEBUG && warn "-> Matched!\n";

        my $orig_path_info   = $env->{PATH_INFO};
        my $orig_script_name = $env->{SCRIPT_NAME};

        $env->{PATH_INFO}  = $path;
        $env->{SCRIPT_NAME} = $script_name . $location;
        return $self->response_cb($app->($env), sub {
            $env->{PATH_INFO} = $orig_path_info;
            $env->{SCRIPT_NAME} = $orig_script_name;
        });
    }

    DEBUG && warn "All matching failed.\n";

    return [404, [ 'Content-Type' => 'text/plain' ], [ "Not Found" ]];
}

1;

__END__

#line 202
