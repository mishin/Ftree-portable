#line 1 "CGI/Parse/PSGI.pm"
package CGI::Parse::PSGI;
use strict;
use base qw(Exporter);
our @EXPORT_OK = qw( parse_cgi_output );

use IO::File; # perl bug: should be loaded to call ->getline etc. on filehandle/PerlIO
use HTTP::Response;

sub parse_cgi_output {
    my $output = shift;

    my $length;
    if (ref $output eq 'SCALAR') {
        $length = length $$output;
        open my $io, "<", $output;
        $output = $io;
    } else {
        open my $tmp, '<&=:perlio:raw', fileno($output) or die $!;
        $output = $tmp;
        $length = -s $output;
    }

    my $headers;
    while ( my $line = $output->getline ) {
        $headers .= $line;
        last if $headers =~ /\x0d?\x0a\x0d?\x0a$/;
    }
    unless ( defined $headers ) {
        $headers = "HTTP/1.1 500 Internal Server Error\x0d\x0a";
    }

    unless ( $headers =~ /^HTTP/ ) {
        $headers = "HTTP/1.1 200 OK\x0d\x0a" . $headers;
    }

    my $response = HTTP::Response->parse($headers);

    # RFC 3875 6.2.3
    if ($response->header('Location') && !$response->header('Status')) {
        $response->header('Status', 302);
    }

    my $status = $response->header('Status') || 200;
    $status =~ s/\s+.*$//; # remove ' OK' in '200 OK'

    $response->remove_header('Status'); # PSGI doesn't allow having Status header in the response

    my $remaining = $length - tell( $output );
    if ( $response->code == 500 && !$remaining ) {
        return [
            500,
            [ 'Content-Type' => 'text/html' ],
            [ $response->error_as_HTML ]
        ];
    }

    # TODO we can pass $output to the response body without buffering all?

    {
        my $length = 0;
        while ( $output->read( my $buffer, 4096 ) ) {
            $length += length($buffer);
            $response->add_content($buffer);
        }

        if ( $length && !$response->content_length ) {
            $response->content_length($length);
        }
    }

    return [
        $status,
        +[
            map {
                my $k = $_;
                map { ( $k => _cleanup_newline($_) ) } $response->headers->header($_);
            } $response->headers->header_field_names
        ],
        [$response->content],
    ];
}

sub _cleanup_newline {
    local $_ = shift;
    s/\r?\n//g;
    return $_;
}

1;

__END__

#line 124
