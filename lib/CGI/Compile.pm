#line 1 "CGI/Compile.pm"
package CGI::Compile;

use strict;
use 5.008_001;

# this helper function is placed at the top of the file to
# hide variables in this file from the generated sub.
sub _eval {
    no strict;
    no warnings;

    eval $_[0];
}

our $VERSION = '0.19';

use Cwd;
use File::Basename;
use File::Spec::Functions;
use File::pushd;

our $RETURN_EXIT_VAL = undef;

sub new {
    my ($class, %opts) = @_;

    $opts{namespace_root} ||= 'CGI::Compile::ROOT';

    bless \%opts, $class;
}

our $USE_REAL_EXIT;
BEGIN {
    $USE_REAL_EXIT = 1;

    my $orig = *CORE::GLOBAL::exit{CODE};

    my $proto = $orig ? prototype $orig : prototype 'CORE::exit';

    $proto = $proto ? "($proto)" : '';

    $orig ||= sub {
        my $exit_code = shift;

        CORE::exit(defined $exit_code ? $exit_code : 0);
    };

    no warnings 'redefine';

    *CORE::GLOBAL::exit = eval qq{
        sub $proto {
            my \$exit_code = shift;

            \$orig->(\$exit_code) if \$USE_REAL_EXIT;

            die [ "EXIT\n", \$exit_code || 0 ]
        };
    };
    die $@ if $@;
}

sub compile {
    my($class, $script, $package) = @_;

    my $self = ref $class ? $class : $class->new;

    my($code, $path, $dir);
    if (ref $script eq 'SCALAR') {
        $code = $$script;
    } else {
        $code = $self->_read_source($script);
        $path = Cwd::abs_path($script);
        $dir  = File::Basename::dirname($path);
    }

    $package ||= $self->_build_package($path || $script);

    my $warnings = $code =~ /^#!.*\s-w\b/ ? 1 : 0;
    $code =~ s/^__END__\r?\n.*//ms;
    $code =~ s/^__DATA__\r?\n(.*)//ms;
    my $data = $1;

    # TODO handle nph and command line switches?
    my $eval = join '',
        "package $package;",
        "sub {",
        'local $CGI::Compile::USE_REAL_EXIT = 0;',
        "\nCGI::initialize_globals() if defined &CGI::initialize_globals;",
        'local ($0, $CGI::Compile::_dir, *DATA);',
        '{ my ($data, $path, $dir) = @_[1..3];',
        ($path ? '$0 = $path;' : ''),
        ($dir  ? '$CGI::Compile::_dir = File::pushd::pushd $dir;' : ''),
        q{open DATA, '<', \$data;},
        '}',
        # NOTE: this is a workaround to fix a problem in Perl 5.10
        q(local @SIG{keys %SIG} = do { no warnings 'uninitialized'; @{[]} = values %SIG };),
        "local \$^W = $warnings;",
        'my $rv = eval {',
        'local @ARGV = @{ $_[4] };', # args to @ARGV
        'local @_    = @{ $_[4] };', # args to @_ as well
        ($path ? "\n#line 1 $path\n" : ''),
        $code,
        "\n};",
        q{
            my $self     = shift;
            my $exit_val = unpack('C', pack('C', sprintf('%.0f', $rv)));
            if ($@) {
                die $@ unless (
                  ref($@) eq 'ARRAY' and
                  $@->[0] eq "EXIT\n"
                );
                my $exit_param = unpack('C', pack('C', sprintf('%.0f', $@->[1])));

                if ($exit_param != 0 && !$CGI::Compile::RETURN_EXIT_VAL && !$self->{return_exit_val}) {
                    die "exited nonzero: $exit_param";
                }

                $exit_val = $exit_param;
            }

            return $exit_val;
        },
        '};';


    my $sub = do {
        no warnings 'uninitialized'; # for 5.8
        # NOTE: this is a workaround to fix a problem in Perl 5.10
        local @SIG{keys %SIG} = @{[]} = values %SIG;
        local $USE_REAL_EXIT = 0;

        my $code = _eval $eval;
        my $exception = $@;

        die "Could not compile $script: $exception" if $exception;

        sub {
            my @args = @_;
            # this is necessary for MSWin32
            local $SIG{__WARN__} = sub { warn(@_) unless $_[0] =~ /^No such signal/ };
            $code->($self, $data, $path, $dir, \@args)
        };
    };

    return $sub;
}

sub _read_source {
    my($self, $file) = @_;

    open my $fh, "<", $file or die "$file: $!";
    return do { local $/; <$fh> };
}

sub _build_package {
    my($self, $path) = @_;

    my ($volume, $dirs, $file) = File::Spec::Functions::splitpath($path);
    my @dirs = File::Spec::Functions::splitdir($dirs);
    my $package = join '_', grep { defined && length } $volume, @dirs, $file;

    # Escape everything into valid perl identifiers
    $package =~ s/([^A-Za-z0-9_])/sprintf("_%2x", unpack("C", $1))/eg;

    # make sure that the sub-package doesn't start with a digit
    $package =~ s/^(\d)/_$1/;

    $package = $self->{namespace_root} . "::$package";
    return $package;
}

1;

__END__



#line 414
