#line 1 "PerlIO/encoding.pm"
package PerlIO::encoding;

use strict;
our $VERSION = '0.18';
our $DEBUG = 0;
$DEBUG and warn __PACKAGE__, " called by ", join(", ", caller), "\n";

#
# Equivalent of this is done in encoding.xs - do not uncomment.
#
# use Encode ();

require XSLoader;
XSLoader::load();

our $fallback =
    Encode::PERLQQ()|Encode::WARN_ON_ERR()|Encode::STOP_AT_PARTIAL();

1;
__END__

#line 54
