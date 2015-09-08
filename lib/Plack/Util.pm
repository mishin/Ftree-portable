#line 1 "Plack/Util.pm"
package Plack::Util;
use strict;
use Carp ();
use Scalar::Util;
use IO::Handle;
use overload ();
use File::Spec ();

sub TRUE()  { 1==1 }
sub FALSE() { !TRUE }

# there does not seem to be a relevant RT or perldelta entry for this
use constant _SPLICE_SAME_ARRAY_SEGFAULT => $] < '5.008007';

sub load_class {
    my($class, $prefix) = @_;

    if ($prefix) {
        unless ($class =~ s/^\+// || $class =~ /^$prefix/) {
            $class = "$prefix\::$class";
        }
    }

    my $file = $class;
    $file =~ s!::!/!g;
    require "$file.pm"; ## no critic

    return $class;
}

sub is_real_fh ($) {
    my $fh = shift;

    {
        no warnings 'uninitialized';
        return FALSE if -p $fh or -c _ or -b _;
    }

    my $reftype = Scalar::Util::reftype($fh) or return;
    if (   $reftype eq 'IO'
        or $reftype eq 'GLOB' && *{$fh}{IO}
    ) {
        # if it's a blessed glob make sure to not break encapsulation with
        # fileno($fh) (e.g. if you are filtering output then file descriptor
        # based operations might no longer be valid).
        # then ensure that the fileno *opcode* agrees too, that there is a
        # valid IO object inside $fh either directly or indirectly and that it
        # corresponds to a real file descriptor.
        my $m_fileno = $fh->fileno;
        return FALSE unless defined $m_fileno;
        return FALSE unless $m_fileno >= 0;

        my $f_fileno = fileno($fh);
        return FALSE unless defined $f_fileno;
        return FALSE unless $f_fileno >= 0;
        return TRUE;
    } else {
        # anything else, including GLOBS without IO (even if they are blessed)
        # and non GLOB objects that look like filehandle objects cannot have a
        # valid file descriptor in fileno($fh) context so may break.
        return FALSE;
    }
}

sub set_io_path {
    my($fh, $path) = @_;
    bless $fh, 'Plack::Util::IOWithPath';
    $fh->path($path);
}

sub content_length {
    my $body = shift;

    return unless defined $body;

    if (ref $body eq 'ARRAY') {
        my $cl = 0;
        for my $chunk (@$body) {
            $cl += length $chunk;
        }
        return $cl;
    } elsif ( is_real_fh($body) ) {
        return (-s $body) - tell($body);
    }

    return;
}

sub foreach {
    my($body, $cb) = @_;

    if (ref $body eq 'ARRAY') {
        for my $line (@$body) {
            $cb->($line) if length $line;
        }
    } else {
        local $/ = \65536 unless ref $/;
        while (defined(my $line = $body->getline)) {
            $cb->($line) if length $line;
        }
        $body->close;
    }
}

sub class_to_file {
    my $class = shift;
    $class =~ s!::!/!g;
    $class . ".pm";
}

sub _load_sandbox {
    my $_file = shift;

    my $_package = $_file;
    $_package =~ s/([^A-Za-z0-9_])/sprintf("_%2x", unpack("C", $1))/eg;

    local $0 = $_file; # so FindBin etc. works
    local @ARGV = ();  # Some frameworks might try to parse @ARGV

    return eval sprintf <<'END_EVAL', $_package;
package Plack::Sandbox::%s;
{
    my $app = do $_file;
    if ( !$app && ( my $error = $@ || $! )) { die $error; }
    $app;
}
END_EVAL
}

sub load_psgi {
    my $stuff = shift;

    local $ENV{PLACK_ENV} = $ENV{PLACK_ENV} || 'development';

    my $file = $stuff =~ /^[a-zA-Z0-9\_\:]+$/ ? class_to_file($stuff) : File::Spec->rel2abs($stuff);
    my $app = _load_sandbox($file);
    die "Error while loading $file: $@" if $@;

    return $app;
}

sub run_app($$) {
    my($app, $env) = @_;

    return eval { $app->($env) } || do {
        my $body = "Internal Server Error";
        $env->{'psgi.errors'}->print($@);
        [ 500, [ 'Content-Type' => 'text/plain', 'Content-Length' => length($body) ], [ $body ] ];
    };
}

sub headers {
    my $headers = shift;
    inline_object(
        iter   => sub { header_iter($headers, @_) },
        get    => sub { header_get($headers, @_) },
        set    => sub { header_set($headers, @_) },
        push   => sub { header_push($headers, @_) },
        exists => sub { header_exists($headers, @_) },
        remove => sub { header_remove($headers, @_) },
        headers => sub { $headers },
    );
}

sub header_iter {
    my($headers, $code) = @_;

    my @headers = @$headers; # copy
    while (my($key, $val) = splice @headers, 0, 2) {
        $code->($key, $val);
    }
}

sub header_get {
    my($headers, $key) = (shift, lc shift);

    return () if not @$headers;

    my $i = 0;

    if (wantarray) {
        return map {
            $key eq lc $headers->[$i++] ? $headers->[$i++] : ++$i && ();
        } 1 .. @$headers/2;
    }

    while ($i < @$headers) {
        return $headers->[$i+1] if $key eq lc $headers->[$i];
        $i += 2;
    }

    ();
}

sub header_set {
    my($headers, $key, $val) = @_;

    @$headers = ($key, $val), return if not @$headers;

    my ($i, $_key) = (0, lc $key);

    # locate and change existing header
    while ($i < @$headers) {
        $headers->[$i+1] = $val, last if $_key eq lc $headers->[$i];
        $i += 2;
    }

    if ($i > $#$headers) { # didn't find it?
        push @$headers, $key, $val;
        return;
    }

    $i += 2; # found and changed it; so, first, skip that pair

    return if $i > $#$headers; # anything left?

    # yes... so do the same thing as header_remove
    # but for the tail of the array only, starting at $i

    my $keep;
    my @keep = grep {
        $_ & 1 ? $keep : ($keep = $_key ne lc $headers->[$_]);
    } $i .. $#$headers;

    my $remainder = @$headers - $i;
    return if @keep == $remainder; # if we're not changing anything...

    splice @$headers, $i, $remainder, ( _SPLICE_SAME_ARRAY_SEGFAULT
        ? @{[ @$headers[@keep] ]} # force different source array
        :     @$headers[@keep]
    );
    ();
}

sub header_push {
    my($headers, $key, $val) = @_;
    push @$headers, $key, $val;
}

sub header_exists {
    my($headers, $key) = (shift, lc shift);

    my $check;
    for (@$headers) {
        return 1 if ($check = not $check) and $key eq lc;
    }

    return !1;
}

sub header_remove {
    my($headers, $key) = (shift, lc shift);

    return if not @$headers;

    my $keep;
    my @keep = grep {
        $_ & 1 ? $keep : ($keep = $key ne lc $headers->[$_]);
    } 0 .. $#$headers;

    @$headers = @$headers[@keep] if @keep < @$headers;
    ();
}

sub status_with_no_entity_body {
    my $status = shift;
    return $status < 200 || $status == 204 || $status == 304;
}

sub encode_html {
    my $str = shift;
    $str =~ s/&/&amp;/g;
    $str =~ s/>/&gt;/g;
    $str =~ s/</&lt;/g;
    $str =~ s/"/&quot;/g;
    $str =~ s/'/&#39;/g;
    return $str;
}

sub inline_object {
    my %args = @_;
    bless \%args, 'Plack::Util::Prototype';
}

sub response_cb {
    my($res, $cb) = @_;

    my $body_filter = sub {
        my($cb, $res) = @_;
        my $filter_cb = $cb->($res);
        # If response_cb returns a callback, treat it as a $body filter
        if (defined $filter_cb && ref $filter_cb eq 'CODE') {
            Plack::Util::header_remove($res->[1], 'Content-Length');
            if (defined $res->[2]) {
                if (ref $res->[2] eq 'ARRAY') {
                    for my $line (@{$res->[2]}) {
                        $line = $filter_cb->($line);
                    }
                    # Send EOF.
                    my $eof = $filter_cb->( undef );
                    push @{ $res->[2] }, $eof if defined $eof;
                } else {
                    my $body    = $res->[2];
                    my $getline = sub { $body->getline };
                    $res->[2] = Plack::Util::inline_object
                        getline => sub { $filter_cb->($getline->()) },
                        close => sub { $body->close };
                }
            } else {
                return $filter_cb;
            }
        }
    };

    if (ref $res eq 'ARRAY') {
        $body_filter->($cb, $res);
        return $res;
    } elsif (ref $res eq 'CODE') {
        return sub {
            my $respond = shift;
            my $cb = $cb;  # To avoid the nested closure leak for 5.8.x
            $res->(sub {
                my $res = shift;
                my $filter_cb = $body_filter->($cb, $res);
                if ($filter_cb) {
                    my $writer = $respond->($res);
                    if ($writer) {
                        return Plack::Util::inline_object
                            write => sub { $writer->write($filter_cb->(@_)) },
                            close => sub {
                                my $chunk = $filter_cb->(undef);
                                $writer->write($chunk) if defined $chunk;
                                $writer->close;
                            };
                    }
                } else {
                    return $respond->($res);
                }
            });
        };
    }

    return $res;
}

package Plack::Util::Prototype;

our $AUTOLOAD;
sub can {
    return $_[0]->{$_[1]} if Scalar::Util::blessed($_[0]);
    goto &UNIVERSAL::can;
}

sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*://;
    if (ref($self->{$attr}) eq 'CODE') {
        $self->{$attr}->(@_);
    } else {
        Carp::croak(qq/Can't locate object method "$attr" via package "Plack::Util::Prototype"/);
    }
}

sub DESTROY { }

package Plack::Util::IOWithPath;
use parent qw(IO::Handle);

sub path {
    my $self = shift;
    if (@_) {
        ${*$self}{+__PACKAGE__} = shift;
    }
    ${*$self}{+__PACKAGE__};
}

package Plack::Util;

1;

__END__

#line 571



