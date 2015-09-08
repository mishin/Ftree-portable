#line 1 "URI/Escape.pm"
package URI::Escape;
use strict;

#line 137

require Exporter;
our @ISA = qw(Exporter);
our %escapes;
our @EXPORT = qw(uri_escape uri_unescape uri_escape_utf8);
our @EXPORT_OK = qw(%escapes);
our $VERSION = "3.31";

use Carp ();

# Build a char->hex map
for (0..255) {
    $escapes{chr($_)} = sprintf("%%%02X", $_);
}

my %subst;  # compiled patterns

my %Unsafe = (
    RFC2732 => qr/[^A-Za-z0-9\-_.!~*'()]/,
    RFC3986 => qr/[^A-Za-z0-9\-\._~]/,
);

sub uri_escape {
    my($text, $patn) = @_;
    return undef unless defined $text;
    if (defined $patn){
        unless (exists  $subst{$patn}) {
            # Because we can't compile the regex we fake it with a cached sub
            (my $tmp = $patn) =~ s,/,\\/,g;
            eval "\$subst{\$patn} = sub {\$_[0] =~ s/([$tmp])/\$escapes{\$1} || _fail_hi(\$1)/ge; }";
            Carp::croak("uri_escape: $@") if $@;
        }
        &{$subst{$patn}}($text);
    } else {
        $text =~ s/($Unsafe{RFC3986})/$escapes{$1} || _fail_hi($1)/ge;
    }
    $text;
}

sub _fail_hi {
    my $chr = shift;
    Carp::croak(sprintf "Can't escape \\x{%04X}, try uri_escape_utf8() instead", ord($chr));
}

sub uri_escape_utf8 {
    my $text = shift;
    utf8::encode($text);
    return uri_escape($text, @_);
}

sub uri_unescape {
    # Note from RFC1630:  "Sequences which start with a percent sign
    # but are not followed by two hexadecimal characters are reserved
    # for future extension"
    my $str = shift;
    if (@_ && wantarray) {
        # not executed for the common case of a single argument
        my @str = ($str, @_);  # need to copy
        for (@str) {
            s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        }
        return @str;
    }
    $str =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $str;
    $str;
}

sub escape_char {
    return join '', @URI::Escape::escapes{$_[0] =~ /(\C)/g};
}

1;
