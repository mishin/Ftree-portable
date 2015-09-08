#line 1 "CGI/Emulate/PSGI.pm"
package CGI::Emulate::PSGI;
use strict;
use warnings;
use CGI::Parse::PSGI;
use POSIX 'SEEK_SET';
use IO::File ();
use SelectSaver;
use Carp qw(croak);
use 5.008001;

our $VERSION = '0.21';

sub handler {
    my ($class, $code, ) = @_;

    return sub {
        my $env = shift;

        my $stdout  = IO::File->new_tmpfile;

        {
            my $saver = SelectSaver->new("::STDOUT");
            {
                local %ENV = (%ENV, $class->emulate_environment($env));

                local *STDIN  = $env->{'psgi.input'};
                local *STDOUT = $stdout;
                local *STDERR = $env->{'psgi.errors'};

                $code->();
            }
        }

        seek( $stdout, 0, SEEK_SET )
            or croak("Can't seek stdout handle: $!");

        return CGI::Parse::PSGI::parse_cgi_output($stdout);
    };
}

sub emulate_environment {
    my($class, $env) = @_;

    no warnings;
    my $environment = {
        GATEWAY_INTERFACE => 'CGI/1.1',
        HTTPS => ( ( $env->{'psgi.url_scheme'} eq 'https' ) ? 'ON' : 'OFF' ),
        SERVER_SOFTWARE => "CGI-Emulate-PSGI",
        REMOTE_ADDR     => '127.0.0.1',
        REMOTE_HOST     => 'localhost',
        REMOTE_PORT     => int( rand(64000) + 1000 ),    # not in RFC 3875
        # REQUEST_URI     => $uri->path_query,                 # not in RFC 3875
        ( map { $_ => $env->{$_} } grep !/^psgix?\./, keys %$env )
    };

    return wantarray ? %$environment : $environment;
}

1;
__END__

#line 176

