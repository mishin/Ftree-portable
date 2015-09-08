#line 1 "Plack/Runner.pm"
package Plack::Runner;
use strict;
use warnings;
use Carp ();
use Plack::Util;
use Try::Tiny;

sub new {
    my $class = shift;
    bless {
        env      => $ENV{PLACK_ENV},
        loader   => 'Plack::Loader',
        includes => [],
        modules  => [],
        default_middleware => 1,
        @_,
    }, $class;
}

# delay the build process for reloader
sub build(&;$) {
    my $block = shift;
    my $app   = shift || sub { };
    return sub { $block->($app->()) };
}

sub parse_options {
    my $self = shift;

    local @ARGV = @_;

    # From 'prove': Allow cuddling the paths with -I, -M and -e
    @ARGV = map { /^(-[IMe])(.+)/ ? ($1,$2) : $_ } @ARGV;

    my($host, $port, $socket, @listen);

    require Getopt::Long;
    my $parser = Getopt::Long::Parser->new(
        config => [ "no_auto_abbrev", "no_ignore_case", "pass_through" ],
    );

    $parser->getoptions(
        "a|app=s"      => \$self->{app},
        "o|host=s"     => \$host,
        "p|port=i"     => \$port,
        "s|server=s"   => \$self->{server},
        "S|socket=s"   => \$socket,
        'l|listen=s@'  => \@listen,
        'D|daemonize'  => \$self->{daemonize},
        "E|env=s"      => \$self->{env},
        "e=s"          => \$self->{eval},
        'I=s@'         => $self->{includes},
        'M=s@'         => $self->{modules},
        'r|reload'     => sub { $self->{loader} = "Restarter" },
        'R|Reload=s'   => sub { $self->{loader} = "Restarter"; $self->loader->watch(split ",", $_[1]) },
        'L|loader=s'   => \$self->{loader},
        "access-log=s" => \$self->{access_log},
        "path=s"       => \$self->{path},
        "h|help"       => \$self->{help},
        "v|version"    => \$self->{version},
        "default-middleware!" => \$self->{default_middleware},
    );

    my(@options, @argv);
    while (defined(my $arg = shift @ARGV)) {
        if ($arg =~ s/^--?//) {
            my @v = split '=', $arg, 2;
            $v[0] =~ tr/-/_/;
            if (@v == 2) {
                push @options, @v;
            } elsif ($v[0] =~ s/^(disable|enable)_//) {
                push @options, $v[0], $1 eq 'enable';
            } else {
                push @options, $v[0], shift @ARGV;
            }
        } else {
            push @argv, $arg;
        }
    }

    push @options, $self->mangle_host_port_socket($host, $port, $socket, @listen);
    push @options, daemonize => 1 if $self->{daemonize};

    $self->{options} = \@options;
    $self->{argv}    = \@argv;
}

sub set_options {
    my $self = shift;
    push @{$self->{options}}, @_;
}

sub mangle_host_port_socket {
    my($self, $host, $port, $socket, @listen) = @_;

    for my $listen (reverse @listen) {
        if ($listen =~ /:\d+$/) {
            ($host, $port) = split /:/, $listen, 2;
            $host = undef if $host eq '';
        } else {
            $socket ||= $listen;
        }
    }

    unless (@listen) {
        if ($socket) {
            @listen = ($socket);
        } else {
            $port ||= 5000;
            @listen = ($host ? "$host:$port" : ":$port");
        }
    }

    return host => $host, port => $port, listen => \@listen, socket => $socket;
}

sub version_cb {
    my $self = shift;
    $self->{version_cb} || sub {
        require Plack;
        print "Plack $Plack::VERSION\n";
    };
}

sub setup {
    my $self = shift;

    if ($self->{help}) {
        require Pod::Usage;
        Pod::Usage::pod2usage(0);
    }

    if ($self->{version}) {
        $self->version_cb->();
        exit;
    }

    if (@{$self->{includes}}) {
        require lib;
        lib->import(@{$self->{includes}});
    }

    if ($self->{eval}) {
        push @{$self->{modules}}, 'Plack::Builder';
    }

    for (@{$self->{modules}}) {
        my($module, @import) = split /[=,]/;
        eval "require $module" or die $@;
        $module->import(@import);
    }
}

sub locate_app {
    my($self, @args) = @_;

    my $psgi = $self->{app} || $args[0];

    if (ref $psgi eq 'CODE') {
        return sub { $psgi };
    }

    if ($self->{eval}) {
        $self->loader->watch("lib");
        return build {
            no strict;
            no warnings;
            my $eval = "builder { $self->{eval};";
            $eval .= "Plack::Util::load_psgi(\$psgi);" if $psgi;
            $eval .= "}";
            eval $eval or die $@;
        };
    }

    $psgi ||= "app.psgi";

    require File::Basename;
    $self->loader->watch( File::Basename::dirname($psgi) . "/lib", $psgi );
    build { Plack::Util::load_psgi $psgi };
}

sub watch {
    my($self, @dir) = @_;

    push @{$self->{watch}}, @dir
        if $self->{loader} eq 'Restarter';
}

sub apply_middleware {
    my($self, $app, $class, @args) = @_;

    my $mw_class = Plack::Util::load_class($class, 'Plack::Middleware');
    build { $mw_class->wrap($_[0], @args) } $app;
}

sub prepare_devel {
    my($self, $app) = @_;

    if ($self->{default_middleware}) {
        $app = $self->apply_middleware($app, 'Lint');
        $app = $self->apply_middleware($app, 'StackTrace');
        if (!$ENV{GATEWAY_INTERFACE} and !$self->{access_log}) {
            $app = $self->apply_middleware($app, 'AccessLog');
        }
    }

    push @{$self->{options}}, server_ready => sub {
        my($args) = @_;
        my $name  = $args->{server_software} || ref($args); # $args is $server
        my $host  = $args->{host} || 0;
        my $proto = $args->{proto} || 'http';
        print STDERR "$name: Accepting connections at $proto://$host:$args->{port}/\n";
    };

    $app;
}

sub loader {
    my $self = shift;
    $self->{_loader} ||= Plack::Util::load_class($self->{loader}, 'Plack::Loader')->new;
}

sub load_server {
    my($self, $loader) = @_;

    if ($self->{server}) {
        return $loader->load($self->{server}, @{$self->{options}});
    } else {
        return $loader->auto(@{$self->{options}});
    }
}

sub run {
    my $self = shift;

    unless (ref $self) {
        $self = $self->new;
        $self->parse_options(@_);
        return $self->run;
    }

    unless ($self->{options}) {
        $self->parse_options();
    }

    my @args = @_ ? @_ : @{$self->{argv}};

    $self->setup;

    my $app = $self->locate_app(@args);

    if ($self->{path}) {
        require Plack::App::URLMap;
        $app = build {
            my $urlmap = Plack::App::URLMap->new;
            $urlmap->mount($self->{path} => $_[0]);
            $urlmap->to_app;
        } $app;
    }

    $ENV{PLACK_ENV} ||= $self->{env} || 'development';
    if ($ENV{PLACK_ENV} eq 'development') {
        $app = $self->prepare_devel($app);
    }

    if ($self->{access_log}) {
        open my $logfh, ">>", $self->{access_log}
            or die "open($self->{access_log}): $!";
        $logfh->autoflush(1);
        $app = $self->apply_middleware($app, 'AccessLog', logger => sub { $logfh->print( @_ ) });
    }

    my $loader = $self->loader;
    $loader->preload_app($app);

    my $server = $self->load_server($loader);
    $loader->run($server);
}

1;

__END__

#line 343


