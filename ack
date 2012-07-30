#!/usr/bin/env perl
#
# This file, ack, is generated code.
# Please DO NOT EDIT or send patches for it.
#
# Please take a look at the source from
# http://github.com/petdance/ack2
# and submit patches against the individual files
# that build ack.
#

use strict;
use warnings;

use 5.8.0;


# XXX Don't make this so brute force

use Carp ();

our $VERSION = '2.00a01';
# Check http://betterthangrep.com/ for updates

# These are all our globals.

MAIN: {
    if ( $App::Ack::VERSION ne $main::VERSION ) {
        App::Ack::die( "Program/library version mismatch\n\t$0 is $main::VERSION\n\t$INC{'App/Ack.pm'} is $App::Ack::VERSION" );
    }

    # Do preliminary arg checking;
    my $env_is_usable = 1;
    for ( @ARGV ) {
        last if ( $_ eq '--' );

        # Get the --thpppt and --bar checking out of the way.
        /^--th[pt]+t+$/ && App::Ack::_thpppt($_);
        /^--bar$/ && App::Ack::_bar();

        # See if we want to ignore the environment. (Don't tell Al Gore.)
        if ( /^--(no)?env$/ ) {
            $env_is_usable = defined $1 ? 0 : 1;
        }
    }
    @ARGV = grep { defined() } @ARGV; # filter out options we discarded
    if ( !$env_is_usable ) {
        my @keys = ( 'ACKRC', grep { /^ACK_/ } keys %ENV );
        delete @ENV{@keys};
    }
    App::Ack::load_colors();

    if ( !@ARGV ) {
        App::Ack::show_help();
        exit 1;
    }

    main();
}

sub _compile_descend_filter {
    my ( $opt ) = @_;

    my $idirs = $opt->{idirs};
    return unless $idirs && @{$idirs};

    my %ignore_dirs;

    foreach my $idir (@{$idirs}) {
        if ( $idir =~ /^(\w+):(.*)/ ) {
            if ( $1 eq 'is') {
                $ignore_dirs{$2} = 1;
            }
            else {
                Carp::croak( 'Non-is filters are not yet supported for --ignore-dir' );
            }
        }
        else {
            Carp::croak( qq{Invalid filter specification "$_"} );
        }
    }

    return sub {
        return !exists $ignore_dirs{$_} && !exists $ignore_dirs{$File::Next::dir};
    };
}

sub _compile_file_filter {
    my ( $opt, $start ) = @_;

    my $ifiles = $opt->{ifiles};
    $ifiles  ||= [];

    my @ifiles_filters = map {
        my $filter;

        if ( /^(\w+):(.+)/ ) {
            my ($how,$what) = ($1,$2);
            $filter = App::Ack::Filter->create_filter($how, split(/,/, $what));
        }
        else {
            Carp::croak( qq{Invalid filter specification "$_"} );
        }
        $filter
    } @{$ifiles};

    my $filters         = $opt->{'filters'} || [];
    my $inverse_filters = [ grep {  $_->is_inverted() } @{$filters} ];
    @{$filters}         =   grep { !$_->is_inverted() } @{$filters};

    my %is_member_of_starting_set = map { ($_ => 1) } @{$start};

    return sub {
        return 1 if $is_member_of_starting_set{ $File::Next::name };

        foreach my $filter (@ifiles_filters) {
            my $resource = App::Ack::Resource::Basic->new($File::Next::name);
            return 0 if ! $resource || $filter->filter($resource);
        }
        my $match_found = 1;
        if ( @{$filters} ) {
            $match_found = 0;

            foreach my $filter (@{$filters}) {
                my $resource = App::Ack::Resource::Basic->new($File::Next::name);
                return 0 if ! $resource;
                if ($filter->filter($resource)) {
                    $match_found = 1;
                    last;
                }
            }
        }
        # Don't bother invoking inverse filters unless we consider the current resource a match
        if ( $match_found && @{$inverse_filters} ) {
            foreach my $filter ( @{$inverse_filters} ) {
                my $resource = App::Ack::Resource::Basic->new($File::Next::name);
                return 0 if ! $resource;
                if ( not $filter->filter( $resource ) ) {
                    $match_found = 0;
                    last;
                }
            }
        }
        return $match_found;
    };
}

sub main {
    my @arg_sources = App::Ack::retrieve_arg_sources();

    my $opt = App::Ack::ConfigLoader::process_args( @arg_sources );

    if ( $opt->{flush} ) {
        $| = 1;
    }

    if ( not defined $opt->{color} ) {
        $opt->{color} = !App::Ack::output_to_pipe() && !$App::Ack::is_windows;
    }
    if ( not defined $opt->{heading} and not defined $opt->{break}  ) {
        $opt->{heading} = $opt->{break} = !App::Ack::output_to_pipe();
    }

    if ( defined($opt->{H}) || defined($opt->{h}) ) {
        $opt->{show_filename}= $opt->{H} && !$opt->{h};
    }

    my $resources;
    if ( $App::Ack::is_filter_mode && !$opt->{files_from} ) { # probably -x
        $resources    = App::Ack::Resources->from_stdin( $opt );
        my $regex = $opt->{regex};
        $regex = shift @ARGV if not defined $regex;
        $opt->{regex} = App::Ack::build_regex( $regex, $opt );
    }
    else {
        if ( $opt->{f} || $opt->{lines} ) {
            if ( $opt->{regex} ) {
                App::Ack::warn( "regex ($opt->{regex}) specified with -f or --lines" );
                App::Ack::exit_from_ack( 0 ); # XXX the 0 is misleading
            }
        }
        else {
            my $regex = $opt->{regex};
            $regex = shift @ARGV if not defined $regex;
            $opt->{regex} = App::Ack::build_regex( $regex, $opt );
        }
        my @start;
        if ( not defined $opt->{files_from} ) {
            @start = @ARGV;
        }
        if ( !exists($opt->{show_filename}) ) {
            unless(@start == 1 && !(-d $start[0])) {
                $opt->{show_filename} = 1;
            }
        }

        if ( defined $opt->{files_from} ) {
            $resources = App::Ack::Resources->from_file( $opt, $opt->{files_from} );
            exit 1 unless $resources;
        }
        else {
            @start = ('.') unless @start;
            foreach my $target (@start) {
                if ( not -e $target ) {
                    App::Ack::warn( "$target: No such file or directory" );
                }
            }

            $opt->{file_filter}    = _compile_file_filter($opt, \@start);
            $opt->{descend_filter} = _compile_descend_filter($opt);

            $resources = App::Ack::Resources->from_argv( $opt, \@start );
        }
    }
    App::Ack::set_up_pager( $opt->{pager} ) if defined $opt->{pager};

    my $print_filenames = $opt->{show_filename};
    my $max_count       = $opt->{m};
    my $ors             = $opt->{print0} ? "\0" : "\n";
    my $only_first      = $opt->{1};

    my $nmatches = 0;
RESOURCES:
    while ( my $resource = $resources->next ) {
        # XXX this variable name combined with what we're trying
        # to do makes no sense.
        if ( $opt->{f} ) {
            # XXX printing should probably happen inside of App::Ack
            if($opt->{show_types}) {
                my @types = App::Ack::filetypes($resource);
                print $resource->name, ' => ', join(',', @types), $ors;
            } else {
                print $resource->name, $ors;
            }
            ++$nmatches;
            last RESOURCES if defined($max_count) && $nmatches >= $max_count;
        }
        elsif ( $opt->{g} ) {
            my $is_match = ( $resource->name =~ /$opt->{regex}/o );
            if ( $opt->{v} ? !$is_match : $is_match ) {
                if($opt->{show_types}) {
                    my @types = App::Ack::filetypes($resource);
                    print $resource->name, ' => ', join(',', @types), $ors;
                } else {
                    print $resource->name, $ors;
                }
                ++$nmatches;
                last RESOURCES if defined($max_count) && $nmatches >= $max_count;
            }
        }
        elsif ( $opt->{lines} ) {
            my $print_filename = $opt->{show_filename};
            my $passthru       = $opt->{passthru};

            my %line_numbers;
            foreach my $line ( @{ $opt->{lines} } ) {
                my @lines             = split /,/, $line;
                @lines                = map {
                    /^(\d+)-(\d+)$/
                        ? ( $1 .. $2 )
                        : $_
                } @lines;
                @line_numbers{@lines} = (1) x @lines;
            }

            my $filename = $resource->name;

            App::Ack::iterate($resource, $opt, sub {
                chomp;

                if ( $line_numbers{$.} ) {
                    App::Ack::print_line_with_context($opt, $filename, $_, $.);
                }
                elsif ( $passthru ) {
                    App::Ack::print_line_with_options($opt, $filename, $_, $., ':');
                }
                return 1;
            });
        }
        elsif ( $opt->{count} ) {
            my $matches_for_this_file = App::Ack::count_matches_in_resource( $resource, $opt );
            if ( !$opt->{l} || $matches_for_this_file > 0) {
                if ( $print_filenames ) {
                    # XXX printing should probably happen inside of App::Ack
                    print $resource->name, ':', $matches_for_this_file, $ors;
                }
                else {
                    # XXX printing should probably happen inside of App::Ack
                    print $matches_for_this_file, $ors;
                }
            }
        }
        elsif ( $opt->{l} ) {
            my $is_match = App::Ack::resource_has_match( $resource, $opt );

            if ( $opt->{v} ? !$is_match : $is_match ) {
                # XXX printing should probably happen inside of App::Ack
                print $resource->name, $ors;
                ++$nmatches;
            }
        }
        else {
            $nmatches += App::Ack::print_matches_in_resource( $resource, $opt );
            if ( $nmatches && $only_first ) {
                last RESOURCES;
            }
        }
    }

    close $App::Ack::fh;
    App::Ack::exit_from_ack( $nmatches );
}


=head1 NAME

ack - grep-like text finder

=head1 SYNOPSIS

    ack [options] PATTERN [FILE...]
    ack -f [options] [DIRECTORY...]

=head1 DESCRIPTION

Ack is designed as a replacement for 99% of the uses of F<grep>.

Ack searches the named input FILEs (or standard input if no files
are named, or the file name - is given) for lines containing a match
to the given PATTERN.  By default, ack prints the matching lines.

Ack can also list files that would be searched, without actually
searching them, to let you take advantage of ack's file-type filtering
capabilities.

=head1 FILE SELECTION

If files are not specified for searching, either on the command
line or piped in with the C<-x> option, I<ack> delves into
subdirectories selecting files for searching.

I<ack> is intelligent about the files it searches.  It knows about
certain file types, based on both the extension on the file and,
in some cases, the contents of the file.  These selections can be
made with the B<--type> option.

With no file selections, I<ack> only searches files of types that
it recognizes.  If you have a file called F<foo.wango>, and I<ack>
doesn't know what a .wango file is, I<ack> won't search it.

By default, I<ack> ignores certain files and directories.  These
include:

=over 4

=item * Backup files: Files matching F<#*#> or ending with F<~>.

=item * Coredumps: Files matching F<core.\d+>

=item * Version control directories like F<.svn> and F<.git>.

=back

Run I<ack> with the C<--dump> option to see what settings are set.

However, I<ack> always searches the files given on the command line,
no matter what type.  If you tell I<ack> to search in a coredump,
it will search in a coredump.

=head1 DIRECTORY SELECTION

I<ack> descends through the directory tree of the starting directories
specified.  However, it will ignore the shadow directories used by
many version control systems, and the build directories used by the
Perl MakeMaker system.  You may add or remove a directory from this
list with the B<--[no]ignore-dir> option. The option may be repeated
to add/remove multiple directories from the ignore list.

For a complete list of directories that do not get searched, run
C<ack --dump>.

=head1 WHEN TO USE GREP

I<ack> trumps I<grep> as an everyday tool 99% of the time, but don't
throw I<grep> away, because there are times you'll still need it.

E.g., searching through huge files looking for regexes that can be
expressed with I<grep> syntax should be quicker with I<grep>.

If your script or parent program uses I<grep> C<--quiet> or C<--silent>
or needs exit 2 on IO error, use I<grep>.

=head1 OPTIONS

=over 4

=item B<-A I<NUM>>, B<--after-context=I<NUM>>

Print I<NUM> lines of trailing context after matching lines.

=item B<-B I<NUM>>, B<--before-context=I<NUM>>

Print I<NUM> lines of leading context before matching lines.

=item B<-C [I<NUM>]>, B<--context[=I<NUM>]>

Print I<NUM> lines (default 2) of context around matching lines.

=item B<-c>, B<--count>

Suppress normal output; instead print a count of matching lines for
each input file.  If B<-l> is in effect, it will only show the
number of lines for each file that has lines matching.  Without
B<-l>, some line counts may be zeroes.

If combined with B<-h> (B<--no-filename>) ack outputs only one total
count.

=item B<--color>, B<--nocolor>

B<--color> highlights the matching text.  B<--nocolor> supresses
the color.  This is on by default unless the output is redirected.

On Windows, this option is off by default unless the
L<Win32::Console::ANSI> module is installed or the C<ACK_PAGER_COLOR>
environment variable is used.

=item B<--color-filename=I<color>>

Sets the color to be used for filenames.

=item B<--color-match=I<color>>

Sets the color to be used for matches.

=item B<--color-lineno=I<color>>

Sets the color to be used for line numbers.

=item B<--column>

Show the column number of the first match.  This is helpful for
editors that can place your cursor at a given position.

=item B<--env>, B<--noenv>

B<--noenv> disables all environment processing. No F<.ackrc> is
read and all environment variables are ignored. By default, F<ack>
considers F<.ackrc> and settings in the environment.

=item B<--flush>

B<--flush> flushes output immediately.  This is off by default
unless ack is running interactively (when output goes to a pipe or
file).

=item B<-f>

Only print the files that would be searched, without actually doing
any searching.  PATTERN must not be specified, or it will be taken
as a path to search.

=item B<--follow>, B<--nofollow>

Follow or don't follow symlinks, other than whatever starting files
or directories were specified on the command line.

This is off by default.

=item B<-g I<REGEX>>

Print files where the relative path + filename matches I<REGEX>.
This option is a convenience shortcut for B<-f> B<-G I<REGEX>>.

The options B<-i>, B<-w>, B<-v>, and B<-Q> do not apply to this
I<REGEX>.

=item B<--group>, B<--nogroup>

B<--group> groups matches by file name with.  This is the default
when used interactively.

B<--nogroup> prints one result per line, like grep.  This is the
default when output is redirected.

=item B<-H>, B<--with-filename>

Print the filename for each match.

=item B<-h>, B<--no-filename>

Suppress the prefixing of filenames on output when multiple files are
searched.

=item B<--help>

Print a short help statement.

=item B<-i>, B<--ignore-case>

Ignore case in the search strings.

This applies only to the PATTERN, not to the regexes given for the B<-g>
and B<-G> options.

=item B<--[no]ignore-dir=I<DIRNAME>>

Ignore directory (as CVS, .svn, etc are ignored). May be used
multiple times to ignore multiple directories. For example, mason
users may wish to include B<--ignore-dir=data>. The B<--noignore-dir>
option allows users to search directories which would normally be
ignored (perhaps to research the contents of F<.svn/props> directories).

The I<DIRNAME> must always be a simple directory name. Nested
directories like F<foo/bar> are NOT supported. You would need to
specify B<--ignore-dir=foo> and then no files from any foo directory
are taken into account by ack unless given explicitly on the command
line.

=item B<--line=I<NUM>>

Only print line I<NUM> of each file. Multiple lines can be given with multiple
B<--line> options or as a comma separated list (B<--line=3,5,7>). B<--line=4-7>
also works. The lines are always output in ascending order, no matter the
order given on the command line.

=item B<-l>, B<--files-with-matches>

Only print the filenames of matching files, instead of the matching text.

=item B<-L>, B<--files-without-matches>

Only print the filenames of files that do I<NOT> match. This is equivalent
to specifying B<-l> and B<-v>.

=item B<--match I<REGEX>>

Specify the I<REGEX> explicitly. This is helpful if you don't want to put the
regex as your first argument, e.g. when executing multiple searches over the
same set of files.

    # search for foo and bar in given files
    ack file1 t/file* --match foo
    ack file1 t/file* --match bar

=item B<-m=I<NUM>>, B<--max-count=I<NUM>>

Stop reading a file after I<NUM> matches.

=item B<--man>

Print this manual page.

=item B<-n>, B<--no-recurse>

No descending into subdirectories.

=item B<-o>

Show only the part of each line matching PATTERN (turns off text
highlighting)

=item B<--output=I<expr>>

Output the evaluation of I<expr> for each line (turns off text
highlighting)

=item B<--pager=I<program>>

Direct ack's output through I<program>.  This can also be specified
via the C<ACK_PAGER> and C<ACK_PAGER_COLOR> environment variables.

Using --pager does not suppress grouping and coloring like piping
output on the command-line does.

=item B<--passthru>

Prints all lines, whether or not they match the expression.  Highlighting
will still work, though, so it can be used to highlight matches while
still seeing the entire file, as in:

    # Watch a log file, and highlight a certain IP address
    $ tail -f ~/access.log | ack --passthru 123.45.67.89

=item B<--print0>

Only works in conjunction with -f, -g, -l or -c (filename output). The filenames
are output separated with a null byte instead of the usual newline. This is
helpful when dealing with filenames that contain whitespace, e.g.

    # remove all files of type html
    ack -f --html --print0 | xargs -0 rm -f

=item B<-Q>, B<--literal>

Quote all metacharacters in PATTERN, it is treated as a literal.

This applies only to the PATTERN, not to the regexes given for the B<-g>
and B<-G> options.

=item B<-r>, B<-R>, B<--recurse>

Recurse into sub-directories. This is the default and just here for
compatibility with grep. You can also use it for turning B<--no-recurse> off.

=item B<--smart-case>, B<--no-smart-case>

Ignore case in the search strings if PATTERN contains no uppercase
characters. This is similar to C<smartcase> in vim. This option is
off by default.

B<-i> always overrides this option.

This applies only to the PATTERN, not to the regexes given for the
B<-g> and B<-G> options.

=item B<--sort-files>

Sorts the found files lexically.  Use this if you want your file
listings to be deterministic between runs of I<ack>.

=item B<--show-types>

Outputs the filetypes that ack associates with each file.

Works with B<-f> and B<-g> options.

=item B<--type=TYPE>, B<--type=noTYPE>

Specify the types of files to include or exclude from a search.
TYPE is a filetype, like I<perl> or I<xml>.  B<--type=perl> can
also be specified as B<--perl>, and B<--type=noperl> can be done
as B<--noperl>.

If a file is of both type "foo" and "bar", specifying --foo and
--nobar will exclude the file, because an exclusion takes precedence
over an inclusion.

Type specifications can be repeated and are ORed together.

See I<ack --help=types> for a list of valid types.

=item B<--type-add I<TYPE>=I<.EXTENSION>[,I<.EXT2>[,...]]>

Files with the given EXTENSION(s) are recognized as being of (the
existing) type TYPE. See also L</"Defining your own types">.


=item B<--type-set I<TYPE>=I<.EXTENSION>[,I<.EXT2>[,...]]>

Files with the given EXTENSION(s) are recognized as being of type
TYPE. This replaces an existing definition for type TYPE.  See also
L</"Defining your own types">.

=item B<-v>, B<--invert-match>

Invert match: select non-matching lines

This applies only to the PATTERN, not to the regexes given for the B<-g>
and B<-G> options.

=item B<--version>

Display version and copyright information.

=item B<-w>, B<--word-regexp>

Force PATTERN to match only whole words.  The PATTERN is wrapped with
C<\b> metacharacters.

This applies only to the PATTERN, not to the regexes given for the B<-g>
and B<-G> options.

=item B<-1>

Stops after reporting first match of any kind.  This is different
from B<--max-count=1> or B<-m1>, where only one match per file is
shown.  Also, B<-1> works with B<-f> and B<-g>, where B<-m> does
not.

=item B<--thpppt>

Display the all-important Bill The Cat logo.  Note that the exact
spelling of B<--thpppppt> is not important.  It's checked against
a regular expression.

=item B<--bar>

Check with the admiral for traps.

=back

=head1 THE .ackrc FILE

The F<.ackrc> file contains command-line options that are prepended
to the command line before processing.  Multiple options may live
on multiple lines.  Lines beginning with a # are ignored.  A F<.ackrc>
might look like this:

    # Always sort the files
    --sort-files

    # Always color, even if piping to a another program
    --color

    # Use "less -r" as my pager
    --pager=less -r

Note that arguments with spaces in them do not need to be quoted,
as they are not interpreted by the shell. Basically, each I<line>
in the F<.ackrc> file is interpreted as one element of C<@ARGV>.

F<ack> looks in your home directory for the F<.ackrc>.  You can
specify another location with the F<ACKRC> variable, below.

If B<--noenv> is specified on the command line, the F<.ackrc> file
is ignored.

=head1 Defining your own types

ack allows you to define your own types in addition to the predefined
types. This is done with command line options that are best put into
an F<.ackrc> file - then you do not have to define your types over and
over again. In the following examples the options will always be shown
on one command line so that they can be easily copy & pasted.

I<ack --perl foo> searches for foo in all perl files. I<ack --help=types>
tells you, that perl files are files ending
in .pl, .pm, .pod or .t. So what if you would like to include .xs
files as well when searching for --perl files? I<ack --type-add perl=.xs --perl foo>
does this for you. B<--type-add> appends
additional extensions to an existing type.

If you want to define a new type, or completely redefine an existing
type, then use B<--type-set>. I<ack --type-set
eiffel=.e,.eiffel> defines the type I<eiffel> to include files with
the extensions .e or .eiffel. So to search for all eiffel files
containing the word Bertrand use I<ack --type-set eiffel=.e,.eiffel --eiffel Bertrand>.
As usual, you can also write B<--type=eiffel>
instead of B<--eiffel>. Negation also works, so B<--noeiffel> excludes
all eiffel files from a search. Redefining also works: I<ack --type-set cc=.c,.h>
and I<.xs> files no longer belong to the type I<cc>.

When defining your own types in the F<.ackrc> file you have to use
the following:

  --type-set=eiffel=.e,.eiffel

or writing on separate lines

  --type-set
  eiffel=.e,.eiffel

The following does B<NOT> work in the F<.ackrc> file:

  --type-set eiffel=.e,.eiffel


In order to see all currently defined types, use I<--help types>, e.g.
I<ack --type-set backup=.bak --type-add perl=.perl --help types>

Restrictions:

=over 4

=item

The shebang line recognition of the types 'perl', 'ruby', 'php',
'python', 'shell' and 'xml' cannot be redefined by I<--type-set>,
it is always active. However, the shebang line is only examined for
files where the extension is not recognised. Therefore it is possible
to say I<ack --type-set perl=.perl --type-set foo=.pl,.pm,.pod,.t
--perl --nofoo> and only find your shiny new I<.perl> files (and
all files with unrecognized extension and perl on the shebang line).

=back

=head1 ENVIRONMENT VARIABLES

For commonly-used ack options, environment variables can make life
much easier.  These variables are ignored if B<--noenv> is specified
on the command line.

=over 4

=item ACKRC

Specifies the location of the F<.ackrc> file.  If this file doesn't
exist, F<ack> looks in the default location.

=item ACK_OPTIONS

This variable specifies default options to be placed in front of
any explicit options on the command line.

=item ACK_COLOR_FILENAME

Specifies the color of the filename when it's printed in B<--group>
mode.  By default, it's "bold green".

The recognized attributes are clear, reset, dark, bold, underline,
underscore, blink, reverse, concealed black, red, green, yellow,
blue, magenta, on_black, on_red, on_green, on_yellow, on_blue,
on_magenta, on_cyan, and on_white.  Case is not significant.
Underline and underscore are equivalent, as are clear and reset.
The color alone sets the foreground color, and on_color sets the
background color.

This option can also be set with B<--color-filename>.

=item ACK_COLOR_MATCH

Specifies the color of the matching text when printed in B<--color>
mode.  By default, it's "black on_yellow".

This option can also be set with B<--color-match>.

See B<ACK_COLOR_FILENAME> for the color specifications.

=item ACK_COLOR_LINENO

Specifies the color of the line number when printed in B<--color>
mode.  By default, it's "bold yellow".

This option can also be set with B<--color-lineno>.

See B<ACK_COLOR_FILENAME> for the color specifications.

=item ACK_PAGER

Specifies a pager program, such as C<more>, C<less> or C<most>, to which
ack will send its output.

Using C<ACK_PAGER> does not suppress grouping and coloring like
piping output on the command-line does, except that on Windows
ack will assume that C<ACK_PAGER> does not support color.

C<ACK_PAGER_COLOR> overrides C<ACK_PAGER> if both are specified.

=item ACK_PAGER_COLOR

Specifies a pager program that understands ANSI color sequences.
Using C<ACK_PAGER_COLOR> does not suppress grouping and coloring
like piping output on the command-line does.

If you are not on Windows, you never need to use C<ACK_PAGER_COLOR>.

=back

=head1 ACK & OTHER TOOLS

=head2 Vim integration

F<ack> integrates easily with the Vim text editor. Set this in your
F<.vimrc> to use F<ack> instead of F<grep>:

    set grepprg=ack\ -a

That examples uses C<-a> to search through all files, but you may
use other default flags. Now you can search with F<ack> and easily
step through the results in Vim:

  :grep Dumper perllib

=head2 Emacs integration

Phil Jackson put together an F<ack.el> extension that "provides a
simple compilation mode ... has the ability to guess what files you
want to search for based on the major-mode."

L<http://www.shellarchive.co.uk/content/emacs.html>

=head2 TextMate integration

Pedro Melo is a TextMate user who writes "I spend my day mostly
inside TextMate, and the built-in find-in-project sucks with large
projects.  So I hacked a TextMate command that was using find +
grep to use ack.  The result is the Search in Project with ack, and
you can find it here:
L<http://www.simplicidade.org/notes/archives/2008/03/search_in_proje.html>"

=head2 Shell and Return Code

For greater compatibility with I<grep>, I<ack> in normal use returns
shell return or exit code of 0 only if something is found and 1 if
no match is found.

(Shell exit code 1 is C<$?=256> in perl with C<system> or backticks.)

The I<grep> code 2 for errors is not used.

If C<-f> or C<-g> are specified, then 0 is returned if at least one
file is found.  If no files are found, then 1 is returned.

=cut

=head1 DEBUGGING ACK PROBLEMS

If ack gives you output you're not expecting, start with a few simple steps.

=head2 Use B<--noenv>

Your environment variables and F<.ackrc> may be doing things you're
not expecting, or forgotten you specified.  Use B<--noenv> to ignore
your environment and F<.ackrc>.

=head2 Use B<-f> to see what files have been selected

Ack's B<-f> was originally added as a debugging tool.  If ack is
not finding matches you think it should find, run F<ack -f> to see
what files have been selected.  You can also add the C<--show-types>
options to show the type of each file selected.

=head1 TIPS

=head2 Use the F<.ackrc> file.

The F<.ackrc> is the place to put all your options you use most of
the time but don't want to remember.  Put all your --type-add and
--type-set definitions in it.  If you like --smart-case, set it
there, too.  I also set --sort-files there.

=head2 Use F<-f> for working with big codesets

Ack does more than search files.  C<ack -f --perl> will create a
list of all the Perl files in a tree, ideal for sending into F<xargs>.
For example:

    # Change all "this" to "that" in all Perl files in a tree.
    ack -f --perl | xargs perl -p -i -e's/this/that/g'

or if you prefer:

    perl -p -i -e's/this/that/g' $(ack -f --perl)

=head2 Use F<-Q> when in doubt about metacharacters

If you're searching for something with a regular expression
metacharacter, most often a period in a filename or IP address, add
the -Q to avoid false positives without all the backslashing.  See
the following example for more...

=head2 Use ack to watch log files

Here's one I used the other day to find trouble spots for a website
visitor.  The user had a problem loading F<troublesome.gif>, so I
took the access log and scanned it with ack twice.

    ack -Q aa.bb.cc.dd /path/to/access.log | ack -Q -B5 troublesome.gif

The first ack finds only the lines in the Apache log for the given
IP.  The second finds the match on my troublesome GIF, and shows
the previous five lines from the log in each case.

=head2 Share your knowledge

Join the ack-users mailing list.  Send me your tips and I may add
them here.

=head1 FAQ

=head2 Why isn't ack finding a match in (some file)?

Probably because it's of a type that ack doesn't recognize.  ack's
searching behavior is driven by filetype.  B<If ack doesn't know
what kind of file it is, ack ignores the file.>

Use the C<-f> switch to see a list of files that ack will search
for you.

If you want ack to search files that it doesn't recognize, use the
C<-a> switch.

If you want ack to search every file, even ones that it always
ignores like coredumps and backup files, use the C<-u> switch.

=head2 Why does ack ignore unknown files by default?

ack is designed by a programmer, for programmers, for searching
large trees of code.  Most codebases have a lot files in them which
aren't source files (like compiled object files, source control
metadata, etc), and grep wastes a lot of time searching through all
of those as well and returning matches from those files.

That's why ack's behavior of not searching things it doesn't recognize
is one of its greatest strengths: the speed you get from only
searching the things that you want to be looking at.

=head2 Wouldn't it be great if F<ack> did search & replace?

No, ack will always be read-only.  Perl has a perfectly good way
to do search & replace in files, using the C<-i>, C<-p> and C<-n>
switches.

You can certainly use ack to select your files to update.  For
example, to change all "foo" to "bar" in all PHP files, you can do
this from the Unix shell:

    $ perl -i -p -e's/foo/bar/g' $(ack -f --php)

=head2 Can you make ack recognize F<.xyz> files?

That's an enhancement.  Please see the section in the manual about
enhancements.

=head2 There's already a program/package called ack.

Yes, I know.

=head2 Why is it called ack if it's called ack-grep?

The name of the program is "ack".  Some packagers have called it
"ack-grep" when creating packages because there's already a package
out there called "ack" that has nothing to do with this ack.

I suggest you make a symlink named F<ack> that points to F<ack-grep>
because one of the crucial benefits of ack is having a name that's
so short and simple to type.

To do that, run this with F<sudo> or as root:

   ln -s /usr/bin/ack-grep /usr/bin/ack

=head2 What does F<ack> mean?

Nothing.  I wanted a name that was easy to type and that you could
pronounce as a single syllable.

=head2 Can I do multi-line regexes?

No, ack does not support regexes that match multiple lines.  Doing
so would require reading in the entire file at a time.

If you want to see lines near your match, use the C<--A>, C<--B>
and C<--C> switches for displaying context.

=head1 ACKRC LOCATION SEMANTICS

Ack can load its configuration from many sources.  This list
specifies the sources Ack looks for configuration; each one
that is found is loaded in the order specified here, and
each one overrides options set in any of the sources preceding
it.  (For example, if I set --sort-files in my user ackrc, and
--nosort-files on the command line, the comand line takes
precedence)

=over 4

=item *

Defaults are loaded from App::Ack::ConfigDefaults.  This can be omitted
using C<--ignore-ack-defaults>.

=item * Global ackrc

Options are then loaded from the global ackrc.  This is located at
C</etc/ackrc> on Unix-like systems, and
C<C:\Documents and Settings\All Users\Application Data> on Windows.
This can be omitted using C<--noenv>.

=item * User ackrc

Options are then loaded from the user's ackrc.  This is located at
C<$HOME/.ackrc> on Unix-like systems, and
C<C:\Documents and Settings\$USER\Application Data>.
This can be omitted using C<--noenv>.

=item * Project ackrc

Options are then loaded from the project ackrc.  The project ackrc is
the first ackrc file with the name C<.ackrc> or C<_ackrc>, first searching
in the current directory, then the parent directory, then the grandparent
directory, etc.  This can be omitted using C<--noenv>.

=item * ACK_OPTIONS

Options are then loaded from the enviroment variable C<ACK_OPTIONS>.  This can
be omitted using C<--noenv>.

=item * Command line

Options are then loaded from the command line.

=back

=head1 AUTHOR

Andy Lester, C<< <andy at petdance.com> >>

=head1 BUGS

Please report any bugs or feature requests to the issues list at
Github: L<https://github.com/petdance/ack/issues>

=head1 ENHANCEMENTS

All enhancement requests MUST first be posted to the ack-users
mailing list at L<http://groups.google.com/group/ack-users>.  I
will not consider a request without it first getting seen by other
ack users.  This includes requests for new filetypes.

There is a list of enhancements I want to make to F<ack> in the ack
issues list at Github: L<https://github.com/petdance/ack/issues>

Patches are always welcome, but patches with tests get the most
attention.

=head1 SUPPORT

Support for and information about F<ack> can be found at:

=over 4

=item * The ack homepage

L<http://betterthangrep.com/>

=item * The ack-users mailing list

L<http://groups.google.com/group/ack-users>

=item * The ack issues list at Github

L<https://github.com/petdance/ack/issues>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/ack>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/ack>

=item * Search CPAN

L<http://search.cpan.org/dist/ack>

=item * Git source repository

L<https://github.com/petdance/ack>

=back

=head1 ACKNOWLEDGEMENTS

How appropriate to have I<ack>nowledgements!

Thanks to everyone who has contributed to ack in any way, including
Shaun Patterson,
Ryan Olson,
Shlomi Fish,
Karen Etheridge,
Olivier Mengue,
Matthew Wild,
Scott Kyle,
Nick Hooey,
Bo Borgerson,
Mark Szymanski,
Marq Schneider,
Packy Anderson,
JR Boyens,
Dan Sully,
Ryan Niebur,
Kent Fredric,
Mike Morearty,
Ingmar Vanhassel,
Eric Van Dewoestine,
Sitaram Chamarty,
Adam James,
Richard Carlsson,
Pedro Melo,
AJ Schuster,
Phil Jackson,
Michael Schwern,
Jan Dubois,
Christopher J. Madsen,
Matthew Wickline,
David Dyck,
Jason Porritt,
Jjgod Jiang,
Thomas Klausner,
Uri Guttman,
Peter Lewis,
Kevin Riggle,
Ori Avtalion,
Torsten Blix,
Nigel Metheringham,
GE<aacute>bor SzabE<oacute>,
Tod Hagan,
Michael Hendricks,
E<AElig>var ArnfjE<ouml>rE<eth> Bjarmason,
Piers Cawley,
Stephen Steneker,
Elias Lutfallah,
Mark Leighton Fisher,
Matt Diephouse,
Christian Jaeger,
Bill Sully,
Bill Ricker,
David Golden,
Nilson Santos F. Jr,
Elliot Shank,
Merijn Broeren,
Uwe Voelker,
Rick Scott,
Ask BjE<oslash>rn Hansen,
Jerry Gay,
Will Coleda,
Mike O'Regan,
Slaven ReziE<0x107>,
Mark Stosberg,
David Alan Pisoni,
Adriano Ferreira,
James Keenan,
Leland Johnson,
Ricardo Signes,
Pete Krawczyk and
Rob Hoelz.

=head1 COPYRIGHT & LICENSE

Copyright 2005-2012 Andy Lester.

This program is free software; you can redistribute it and/or modify
it under the terms of the Artistic License v2.0.

=cut
package File::Next;

use strict;
use warnings;


our $VERSION = '1.10';



use File::Spec ();

our $name; # name of the current file
our $dir;  # dir of the current file

our %files_defaults;
our %skip_dirs;

BEGIN {
    %files_defaults = (
        file_filter     => undef,
        descend_filter  => undef,
        error_handler   => sub { CORE::die @_ },
        warning_handler => sub { CORE::warn @_ },
        sort_files      => undef,
        follow_symlinks => 1,
        nul_separated   => 0,
    );
    %skip_dirs = map {($_,1)} (File::Spec->curdir, File::Spec->updir);
}


sub files {
    die _bad_invocation() if @_ && defined($_[0]) && ($_[0] eq __PACKAGE__);

    my ($parms,@queue) = _setup( \%files_defaults, @_ );
    my $filter = $parms->{file_filter};

    return sub {
        while (@queue) {
            my ($dirname,$file,$fullpath) = splice( @queue, 0, 3 );
            if ( -f $fullpath || -p $fullpath ) {
                if ( $filter ) {
                    local $_ = $file;
                    local $File::Next::dir = $dirname;
                    local $File::Next::name = $fullpath;
                    next if not $filter->();
                }
                return wantarray ? ($dirname,$file,$fullpath) : $fullpath;
            }
            elsif ( -d _ ) {
                unshift( @queue, _candidate_files( $parms, $fullpath ) );
            }
        } # while

        return;
    }; # iterator
}






sub from_file {
    die _bad_invocation() if @_ && defined($_[0]) && ($_[0] eq __PACKAGE__);

    my ($parms,@queue) = _setup( \%files_defaults, @_ );
    my $err  = $parms->{error_handler};
    my $warn = $parms->{error_handler};

    my $filename = $queue[1];

    if ( !defined($filename) ) {
        $err->( 'Must pass a filename to from_file()' );
        return undef;
    }

    my $fh;
    if ( $filename eq '-' ) {
        $fh = \*STDIN;
    }
    else {
        if ( !open( $fh, '<', $filename ) ) {
            $err->( "Unable to open $filename: $!" );
            return undef;
        }
    }
    my $filter = $parms->{file_filter};

    return sub {
        local $/ = $parms->{nul_separated} ? "\x00" : $/;
        while ( my $fullpath = <$fh> ) {
            chomp $fullpath;
            next unless $fullpath =~ /./;
            if ( not ( -f $fullpath || -p _ ) ) {
                $warn->( "$fullpath: No such file" );
                next;
            }

            my ($volume,$dirname,$file) = File::Spec->splitpath( $fullpath );
            if ( $filter ) {
                local $_ = $file;
                local $File::Next::dir  = $dirname;
                local $File::Next::name = $fullpath;
                next if not $filter->();
            }
            return wantarray ? ($dirname,$file,$fullpath) : $fullpath;
        } # while
        close $fh;

        return;
    }; # iterator
}

sub _bad_invocation {
    my $good = (caller(1))[3];
    my $bad  = $good;
    $bad =~ s/(.+)::/$1->/;
    return "$good must not be invoked as $bad";
}

sub sort_standard($$)   { return $_[0]->[1] cmp $_[1]->[1] }
sub sort_reverse($$)    { return $_[1]->[1] cmp $_[0]->[1] }

sub reslash {
    my $path = shift;

    my @parts = split( /\//, $path );

    return $path if @parts < 2;

    return File::Spec->catfile( @parts );
}



sub _setup {
    my $defaults = shift;
    my $passed_parms = ref $_[0] eq 'HASH' ? {%{+shift}} : {}; # copy parm hash

    my %passed_parms = %{$passed_parms};

    my $parms = {};
    for my $key ( keys %{$defaults} ) {
        $parms->{$key} =
            exists $passed_parms{$key}
                ? delete $passed_parms{$key}
                : $defaults->{$key};
    }

    # Any leftover keys are bogus
    for my $badkey ( keys %passed_parms ) {
        my $sub = (caller(1))[3];
        $parms->{error_handler}->( "Invalid option passed to $sub(): $badkey" );
    }

    # If it's not a code ref, assume standard sort
    if ( $parms->{sort_files} && ( ref($parms->{sort_files}) ne 'CODE' ) ) {
        $parms->{sort_files} = \&sort_standard;
    }
    my @queue;

    for ( @_ ) {
        my $start = reslash( $_ );
        if (-d $start) {
            push @queue, ($start,undef,$start);
        }
        else {
            push @queue, (undef,$start,$start);
        }
    }

    return ($parms,@queue);
}


sub _candidate_files {
    my $parms   = shift;
    my $dirname = shift;

    my $dh;
    if ( !opendir $dh, $dirname ) {
        $parms->{error_handler}->( "$dirname: $!" );
        return;
    }

    my @newfiles;
    my $descend_filter = $parms->{descend_filter};
    my $follow_symlinks = $parms->{follow_symlinks};
    my $sort_sub = $parms->{sort_files};

    for my $file ( grep { !exists $skip_dirs{$_} } readdir $dh ) {
        my $has_stat;

        # Only do directory checking if we have a descend_filter
        my $fullpath = File::Spec->catdir( $dirname, $file );
        if ( !$follow_symlinks ) {
            next if -l $fullpath;
            $has_stat = 1;
        }

        if ( $descend_filter ) {
            if ( $has_stat ? (-d _) : (-d $fullpath) ) {
                local $File::Next::dir = $fullpath;
                local $_ = $file;
                next if not $descend_filter->();
            }
        }
        if ( $sort_sub ) {
            push( @newfiles, [ $dirname, $file, $fullpath ] );
        }
        else {
            push( @newfiles, $dirname, $file, $fullpath );
        }
    }
    closedir $dh;

    if ( $sort_sub ) {
        return map { @{$_} } sort $sort_sub @newfiles;
    }

    return @newfiles;
}


1; # End of File::Next
package App::Ack;

use warnings;
use strict;

use Getopt::Long;


our $VERSION;
our $COPYRIGHT;
BEGIN {
    $VERSION = '2.00a01';
    $COPYRIGHT = 'Copyright 2005-2012 Andy Lester.';
}

our $fh;

BEGIN {
    $fh = *STDOUT;
}


our %types;
our %type_wanted;
our %mappings;
our %ignore_dirs;

our $is_filter_mode;
our $output_to_pipe;

our $dir_sep_chars;
our $is_cygwin;
our $is_windows;

use File::Spec ();
use File::Glob ':glob';
use Getopt::Long ();

BEGIN {
    # These have to be checked before any filehandle diddling.
    $output_to_pipe  = not -t *STDOUT;
    $is_filter_mode = -p STDIN;

    $is_cygwin       = ($^O eq 'cygwin');
    $is_windows      = ($^O =~ /MSWin32/);
    $dir_sep_chars   = $is_windows ? quotemeta( '\\/' ) : quotemeta( File::Spec->catfile( '', '' ) );
}


sub retrieve_arg_sources {
    my @arg_sources;

    my $noenv;
    my $ackrc;

    Getopt::Long::Configure('default');
    Getopt::Long::Configure('pass_through');
    Getopt::Long::Configure('no_auto_abbrev');

    GetOptions(
        'noenv'   => \$noenv,
        'ackrc=s' => \$ackrc,
    );

    Getopt::Long::Configure('default');

    my @files;

    if ( !$noenv ) {
        my $finder = App::Ack::ConfigFinder->new;
        @files  = $finder->find_config_files;
    }
    if ( $ackrc ) {
        # we explicitly use open so we get a nice error message
        # XXX this is a potential race condition!
        if(open my $fh, '<', $ackrc) {
            close $fh;
        } else {
            die "Unable to load ackrc '$ackrc': $!"
        }
        push( @files, $ackrc );
    }

    push @arg_sources, Defaults => [ App::Ack::ConfigDefault::options() ];

    foreach my $file ( @files) {
        my @lines = read_rcfile($file);
        push ( @arg_sources, $file, \@lines ) if @lines;
    }

    if ( $ENV{ACK_OPTIONS} && !$noenv ) {
        push( @arg_sources, 'ACK_OPTIONS' => $ENV{ACK_OPTIONS} );
    }

    push( @arg_sources, 'ARGV' => [ @ARGV ] );

    return @arg_sources;
}

sub read_rcfile {
    my $file = shift;

    return unless defined $file && -e $file;

    my @lines;

    open( my $fh, '<', $file ) or App::Ack::die( "Unable to read $file: $!" );
    while ( my $line = <$fh> ) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;

        next if $line eq '';
        next if $line =~ /^#/;

        push( @lines, $line );
    }
    close $fh;

    return @lines;
}


sub create_ignore_rules {
    my $what  = shift;
    my $where = shift;
    my $opts  = shift;

    my @opts = @{$opts};

    my %rules = {
    };

    for my $opt ( @opts ) {
        if ( $opt =~ /^(is|ext|regex),(.+)$/ ) {
            my $method = $1;
            my $arg    = $2;
            if ( $method eq 'regex' ) {
                push( @{$rules{regex}}, qr/$arg/ );
            }
            else {
                ++$rules{$method}{$arg};
            }
        }
        else {
            App::Ack::die( "Invalid argument for --$what: $opt" );
        }
    }

    return \%rules;
}


sub remove_dir_sep {
    my $path = shift;
    $path =~ s/[$dir_sep_chars]$//;

    return $path;
}


sub build_regex {
    my $str = shift;
    my $opt = shift;

    defined $str or App::Ack::die( 'No regular expression found.' );

    $str = quotemeta( $str ) if $opt->{Q};
    if ( $opt->{w} ) {
        $str = "\\b$str" if $str =~ /^\w/;
        $str = "$str\\b" if $str =~ /\w$/;
    }

    my $regex_is_lc = $str eq lc $str;
    if ( $opt->{i} || ($opt->{smart_case} && $regex_is_lc) ) {
        $str = "(?i)$str";
    }

    my $ok = eval {
        qr/$str/
    };

    my $error = $@;

    if ( !$ok ) {
        die "Invalid regex '$str':\n  $error";
    }

    return $str;
}


sub check_regex {
    my $regex = shift;

    return unless defined $regex;

    eval { qr/$regex/ };
    if ($@) {
        (my $error = $@) =~ s/ at \S+ line \d+.*//;
        chomp($error);
        App::Ack::die( "Invalid regex '$regex':\n  $error" );
    }

    return;
}




sub warn {
    return CORE::warn( _my_program(), ': ', @_, "\n" );
}


sub die {
    return CORE::die( _my_program(), ': ', @_, "\n" );
}

sub _my_program {
    require File::Basename;
    return File::Basename::basename( $0 );
}



sub filetypes_supported {
    return keys %mappings;
}

sub _get_thpppt {
    my $y = q{_   /|,\\'!.x',=(www)=,   U   };
    $y =~ tr/,x!w/\nOo_/;
    return $y;
}

sub _thpppt {
    my $y = _get_thpppt();
    App::Ack::print( "$y ack $_[0]!\n" );
    exit 0;
}

sub _bar {
    my $x;
    $x = <<'_BAR';
 6?!I'7!I"?%+!
 3~!I#7#I"7#I!?!+!="+"="+!:!
 2?#I!7!I!?#I!7!I"+"=%+"=#
 1?"+!?*+!=#~"=!+#?"="+!
 0?"+!?"I"?&+!="~!=!~"=!+%="+"
 /I!+!?)+!?!+!=$~!=!~!="+!="+"?!="?!
 .?%I"?%+%='?!=#~$="
 ,,!?%I"?(+$=$~!=#:"~$:!~!
 ,I!?!I!?"I"?!+#?"+!?!+#="~$:!~!:!~!:!,!:!,":#~!
 +I!?&+!="+!?#+$=!~":!~!:!~!:!,!:#,!:!,%:"
 *+!I!?!+$=!+!=!+!?$+#=!~":!~":#,$:",#:!,!:!
 *I!?"+!?!+!=$+!?#+#=#~":$,!:",!:!,&:"
 )I!?$=!~!=#+"?!+!=!+!=!~!="~!:!~":!,'.!,%:!~!
 (=!?"+!?!=!~$?"+!?!+!=#~"=",!="~$,$.",#.!:!=!
 (I"+"="~"=!+&=!~"=!~!,!~!+!=!?!+!?!=!I!?!+"=!.",!.!,":!
 %I$?!+!?!=%+!~!+#~!=!~#:#=!~!+!~!=#:!,%.!,!.!:"
 $I!?!=!?!I!+!?"+!=!~!=!~!?!I!?!=!+!=!~#:",!~"=!~!:"~!=!:",&:" '-/
 $?!+!I!?"+"=!+"~!,!:"+#~#:#,"=!~"=!,!~!,!.",!:".!:! */! !I!t!'!s! !a! !g!r!e!p!!! !/!
 $+"=!+!?!+"~!=!:!~!:"I!+!,!~!=!:!~!,!:!,$:!~".&:"~!,# (-/
 %~!=!~!=!:!.!+"~!:!,!.!,!~!=!:$.!,":!,!.!:!~!,!:!=!.#="~!,!:" ./!
 %=!~!?!+"?"+!=!~",!.!:!?!~!.!:!,!:!,#.!,!:","~!:!=!~!=!:",!~! ./!
 %+"~":!~!=#~!:!~!,!.!~!:",!~!=!~!.!:!,!.",!:!,":!=":!.!,!:!7! -/!
 %~",!:".#:!=!:!,!:"+!:!~!:!.!,!~!,!.#,!.!,$:"~!,":"~!=! */!
 &=!~!=#+!=!~",!.!:",#:#,!.",+:!,!.",!=!+!?!
 &~!=!~!=!~!:"~#:",!.!,#~!:!.!+!,!.",$.",$.#,!+!I!?!
 &~!="~!:!~":!~",!~!=!~":!,!:!~!,!:!,&.$,#."+!?!I!?!I!
 &~!=!~!=!+!,!:!~!:!=!,!:!~&:$,!.!,".!,".!,#."~!+!?$I!
 &~!=!~!="~!=!:!~":!,!~%:#,!:",!.!,#.",#I!7"I!?!+!?"I"
 &+!I!7!:#~"=!~!:!,!:"~$.!=!.!,!~!,$.#,!~!7!I#?!+!?"I"7!
 %7#?!+!~!:!=!~!=!~":!,!:"~":#.!,)7#I"?"I!7&
 %7#I!=":!=!~!:"~$:"~!:#,!:!,!:!~!:#,!7#I!?#7)
 $7$+!,!~!=#~!:!~!:!~$:#,!.!~!:!=!,":!7#I"?#7+=!?!
 $7#I!~!,!~#=!~!:"~!:!,!:!,#:!=!~",":!7$I!?#I!7*+!=!+"
 "I!7$I!,":!,!.!=":$,!:!,$:$7$I!+!?"I!7+?"I!7!I!7!,!
 !,!7%I!:",!."~":!,&.!,!:!~!I!7$I!+!?"I!7,?!I!7',!
 !7(,!.#~":!,%.!,!7%I!7!?#I"7,+!?!7*
7+:!,!~#,"=!7'I!?#I"7/+!7+
77I!+!7!?!7!I"71+!7,
_BAR

    $x =~ s/(.)(.)/$1x(ord($2)-32)/eg;
    App::Ack::print( $x );
    exit 0;
}


sub show_help {
    my $help_arg = shift || 0;

#   return show_help_types() if $help_arg =~ /^types?/;

    App::Ack::print( <<"END_OF_HELP" );
Usage: ack [OPTION]... PATTERN [FILES OR DIRECTORIES]

Search for PATTERN in each source file in the tree from the current
directory on down.  If any files or directories are specified, then
only those files and directories are checked.  ack may also search
STDIN, but only if no file or directory arguments are specified,
or if one of them is "-".

Default switches may be specified in ACK_OPTIONS environment variable or
an .ackrc file. If you want no dependency on the environment, turn it
off with --noenv.

Example: ack -i select

Searching:
  -i, --ignore-case     Ignore case distinctions in PATTERN
  --[no]smart-case      Ignore case distinctions in PATTERN,
                        only if PATTERN contains no upper case
                        Ignored if -i is specified
  -v, --invert-match    Invert match: select non-matching lines
  -w, --word-regexp     Force PATTERN to match only whole words
  -Q, --literal         Quote all metacharacters; PATTERN is literal

Search output:
  --line=NUM            Only print line(s) NUM of each file
  -l, --files-with-matches
                        Only print filenames containing matches
  -L, --files-without-matches
                        Only print filenames with no matches
  --output=expr         Output the evaluation of expr for each line
                        (turns off text highlighting)
  -o                    Show only the part of a line matching PATTERN
                        Same as --output='\$&'
  --passthru            Print all lines, whether matching or not
  --match PATTERN       Specify PATTERN explicitly.
  -m, --max-count=NUM   Stop searching in each file after NUM matches
  -1                    Stop searching after one match of any kind
  -H, --with-filename   Print the filename for each match
  -h, --no-filename     Suppress the prefixing filename on output
  -c, --count           Show number of lines matching per file
  --column              Show the column number of the first match

  -A NUM, --after-context=NUM
                        Print NUM lines of trailing context after matching
                        lines.
  -B NUM, --before-context=NUM
                        Print NUM lines of leading context before matching
                        lines.
  -C [NUM], --context[=NUM]
                        Print NUM lines (default 2) of output context.

  --print0              Print null byte as separator between filenames,
                        only works with -f, -g, -l, -L or -c.


File presentation:
  --pager=COMMAND       Pipes all ack output through COMMAND.  For example,
                        --pager="less -R".  Ignored if output is redirected.
  --nopager             Do not send output through a pager.  Cancels any
                        setting in ~/.ackrc, ACK_PAGER or ACK_PAGER_COLOR.
  --[no]heading         Print a filename heading above each file's results.
                        (default: on when used interactively)
  --[no]break           Print a break between results from different files.
                        (default: on when used interactively)
  --group               Same as --heading --break
  --nogroup             Same as --noheading --nobreak
  --[no]color           Highlight the matching text (default: on unless
                        output is redirected, or on Windows)
  --[no]colour          Same as --[no]color
  --color-filename=COLOR
  --color-match=COLOR
  --color-lineno=COLOR  Set the color for filenames, matches, and line numbers.
  --flush               Flush output immediately, even when ack is used
                        non-interactively (when output goes to a pipe or
                        file).


File finding:
  -f                    Only print the files found, without searching.
                        The PATTERN must not be specified.
  -g                    Same as -f, but only print files matching PATTERN.
  --sort-files          Sort the found files lexically.
  --show-types          Show which types each file has.
  --files-from=FILE     Read the list of files to search from FILE.
  -x                    Read the list of files to search from STDIN.

File inclusion/exclusion:
  --[no]ignore-dir=name Add/Remove directory from the list of ignored dirs
  -r, -R, --recurse     Recurse into subdirectories (ack's default behavior)
  -n, --no-recurse      No descending into subdirectories
  --[no]follow          Follow symlinks.  Default is off.

  --type=X              Include only X files, where X is a recognized filetype.
  --type=noX            Exclude X files.
                        See "ack --help type" for supported filetypes.

File type specification:
  --type-set TYPE=.EXTENSION[,.EXT2[,...]]
                        Files with the given EXTENSION(s) are recognized as
                        being of type TYPE. This replaces an existing
                        definition for type TYPE.
  --type-add TYPE=.EXTENSION[,.EXT2[,...]]
                        Files with the given EXTENSION(s) are recognized as
                        being of (the existing) type TYPE



Miscellaneous:
  --noenv               Ignore environment variables and global ackrc files
  --ackrc=filename      Specify an ackrc file to use
  --ignore-ack-defaults Ignore the default definitions that ack includes.
  --help                This help
  --dump                Dump information on which options are loaded from which RC files
  --man                 Man page
  --version             Display version & copyright
  --thpppt              Bill the Cat
  --bar                 The warning admiral

Exit status is 0 if match, 1 if no match.

This is version $VERSION of ack.
END_OF_HELP

    return;
 }



sub show_help_types {
    App::Ack::print( <<'END_OF_HELP' );
Usage: ack [OPTION]... PATTERN [FILES OR DIRECTORIES]

The following is the list of filetypes supported by ack.  You can
specify a file type with the --type=TYPE format, or the --TYPE
format.  For example, both --type=perl and --perl work.

Note that some extensions may appear in multiple types.  For example,
.pod files are both Perl and Parrot.

END_OF_HELP

    my @types = filetypes_supported();
    my $maxlen = 0;
    for ( @types ) {
        $maxlen = length if $maxlen < length;
    }
    for my $type ( sort @types ) {
        next if $type =~ /^-/; # Stuff to not show
        my $ext_list = $mappings{$type};

        if ( ref $ext_list ) {
            $ext_list = join( ' ', map { $_->to_string } @{$ext_list} );
        }
        App::Ack::print( sprintf( "    --[no]%-*.*s %s\n", $maxlen, $maxlen, $type, $ext_list ) );
    }

    return;
}

sub _listify {
    my @whats = @_;

    return '' if !@whats;

    my $end = pop @whats;
    my $str = @whats ? join( ', ', @whats ) . " and $end" : $end;

    no warnings 'once';
    require Text::Wrap;
    $Text::Wrap::columns = 75;
    return Text::Wrap::wrap( '', '    ', $str );
}


sub get_version_statement {
    require Config;

    my $copyright = get_copyright();
    my $this_perl = $Config::Config{perlpath};
    if ($^O ne 'VMS') {
        my $ext = $Config::Config{_exe};
        $this_perl .= $ext unless $this_perl =~ m/$ext$/i;
    }
    my $ver = sprintf( '%vd', $^V );

    return <<"END_OF_VERSION";
ack $VERSION
Running under Perl $ver at $this_perl

$copyright

This program is free software.  You may modify or distribute it
under the terms of the Artistic License v2.0.
END_OF_VERSION
}


sub print_version_statement {
    App::Ack::print( get_version_statement() );

    return;
}


sub get_copyright {
    return $COPYRIGHT;
}


sub load_colors {
    eval 'use Term::ANSIColor ()';

    $ENV{ACK_COLOR_MATCH}    ||= 'black on_yellow';
    $ENV{ACK_COLOR_FILENAME} ||= 'bold green';
    $ENV{ACK_COLOR_LINENO}   ||= 'bold yellow';

    return;
}


# print subs added in order to make it easy for a third party
# module (such as App::Wack) to redefine the display methods
# and show the results in a different way.
sub print                   { print {$fh} @_; return; }
sub print_first_filename    { App::Ack::print( $_[0], "\n" ); return; }
sub print_blank_line        { App::Ack::print( "\n" ); return; }
sub print_separator         { App::Ack::print( "--\n" ); return; }
sub print_filename          { App::Ack::print( $_[0], $_[1] ); return; }
sub print_line_no           { App::Ack::print( $_[0], $_[1] ); return; }
sub print_column_no         { App::Ack::print( $_[0], $_[1] ); return; }
sub print_count {
    my $filename = shift;
    my $nmatches = shift;
    my $ors = shift;
    my $count = shift;
    my $show_filename = shift;

    if ($show_filename) {
        App::Ack::print( $filename );
        App::Ack::print( ':', $nmatches ) if $count;
    }
    else {
        App::Ack::print( $nmatches ) if $count;
    }
    App::Ack::print( $ors );

    return;
}

sub print_count0 {
    my $filename = shift;
    my $ors = shift;
    my $show_filename = shift;

    if ($show_filename) {
        App::Ack::print( $filename, ':0', $ors );
    }
    else {
        App::Ack::print( '0', $ors );
    }

    return;
}

sub set_up_pager {
    my $command = shift;

    return if App::Ack::output_to_pipe();

    my $pager;
    if ( not open( $pager, '|-', $command ) ) {
        App::Ack::die( qq{Unable to pipe to pager "$command": $!} );
    }
    $fh = $pager;

    return;
}


sub output_to_pipe {
    return $output_to_pipe;
}


sub exit_from_ack {
    my $nmatches = shift;

    my $rc = $nmatches ? 0 : 1;
    exit $rc;
}

{

my @capture_indices;
my $match_column_number;

sub does_match {
    my ( $opt, $line ) = @_;

    my $re     = $opt->{regex};
    my $invert = $opt->{v};

    $match_column_number = undef;
    @capture_indices     = ();

    if ( $invert ? $line !~ /$re/ : $line =~ /$re/ ) {
        if ( not $invert ) {
            use English '-no_match_vars';

            $match_column_number = $LAST_MATCH_START[0] + 1;

            if ( @LAST_MATCH_START > 1 ) {
                @capture_indices = map {
                    [ $LAST_MATCH_START[$_], $LAST_MATCH_END[$_] ]
                } ( 1 .. $#LAST_MATCH_START );
            }
        }
        return 1;
    }
    else {
        return;
    }
}

sub get_capture_indices {
    return @capture_indices;
}

sub get_match_column {
    return $match_column_number;
}

}

sub print_matches_in_resource {
    my ( $resource, $opt ) = @_;

    my $passthru       = $opt->{passthru};
    my $max_count      = $opt->{m} || -1;
    my $nmatches       = 0;
    my $filename       = $resource->name;
    my $break          = $opt->{break};
    my $heading        = $opt->{heading};
    my $ors            = $opt->{print0} ? "\0" : "\n";
    my $color          = $opt->{color};
    my $print_filename = $opt->{show_filename};

    my $has_printed_for_this_resource = 0;

    App::Ack::iterate($resource, $opt, sub {
        if ( App::Ack::does_match($opt, $_) ) {
            if( !$has_printed_for_this_resource ) {
                if( $break && has_printed_something() ) {
                    App::Ack::print_blank_line();
                }
                if( $print_filename) {
                    if( $heading ) {
                        my $filename = $resource->name;
                        if($color) {
                            $filename = Term::ANSIColor::colored($filename,
                                $ENV{ACK_COLOR_FILENAME});
                        }
                        App::Ack::print_filename( $filename, $ors );
                    }
                }
            }
            App::Ack::print_line_with_context($opt, $filename, $_, $.);
            $has_printed_for_this_resource = 1;
            $nmatches++;
            $max_count--;
        }
        elsif ( $passthru ) {
            chomp;
            if( $break && !$has_printed_for_this_resource && has_printed_something() ) {
                App::Ack::print_blank_line();
            }
            App::Ack::print_line_with_options($opt, $filename, $_, $., ':');
            $has_printed_for_this_resource = 1;
        }
        return $max_count != 0;
    });

    return $nmatches;
}

sub count_matches_in_resource {
    my ( $resource, $opt ) = @_;

    my $nmatches = 0;

    App::Ack::iterate( $resource, $opt, sub {
        ++$nmatches if App::Ack::does_match($opt, $_);
        return 1;
    } );

    return $nmatches;
}

sub resource_has_match {
    my ( $resource, $opt ) = @_;

    my $stash_v = $opt->{v};
    $opt->{v} = 0;

    my $n = count_matches_in_resource($resource, $opt) > 0;

    $opt->{v} = $stash_v;

    return $n;
}

{

my @before_ctx_lines;
my @after_ctx_lines;
my $is_iterating;

sub get_context {
    if ( not $is_iterating ) {
        Carp::croak( 'get_context() called outside of iterate()' );
    }

    return (
        scalar(@before_ctx_lines) ? \@before_ctx_lines : undef,
        scalar(@after_ctx_lines)  ? \@after_ctx_lines  : undef,
    );
}

sub iterate {
    my ( $resource, $opt, $cb ) = @_;

    $is_iterating = 1;

    local $opt->{before_context} = $opt->{output} ? 0 : $opt->{before_context};
    local $opt->{after_context}  = $opt->{output} ? 0 : $opt->{after_context};

    my $n_before_ctx_lines = $opt->{before_context} || 0;
    my $n_after_ctx_lines  = $opt->{after_context}  || 0;
    my $current_line;

    @after_ctx_lines = @before_ctx_lines = ();

    if ( $resource->next_text() ) {
        $current_line = $_; # prime the first line of input
    }

    while ( defined $current_line ) {
        while ( (@after_ctx_lines < $n_after_ctx_lines) && $resource->next_text() ) {
            push @after_ctx_lines, $_;
        }

        local $_ = $current_line;
        local $. = $. - @after_ctx_lines;

        last unless $cb->();

        push @before_ctx_lines, $current_line;

        if($n_after_ctx_lines) {
            $current_line = shift @after_ctx_lines;
        }
        elsif($resource->next_text()) {
            $current_line = $_;
        }
        else {
            undef $current_line;
        }
        shift @before_ctx_lines while @before_ctx_lines > $n_before_ctx_lines;
    }

    $is_iterating = 0;

    return;
}

}

my $has_printed_something;

BEGIN {
    $has_printed_something = 0;
}

sub has_printed_something {
    return $has_printed_something;
}

sub print_line_with_options {
    my ( $opt, $filename, $line, $line_no, $separator ) = @_;

    $has_printed_something = 1;

    my $print_filename = $opt->{show_filename};
    my $print_column   = $opt->{column};
    my $ors            = $opt->{print0} ? "\0" : "\n";
    my $heading        = $opt->{heading};
    my $output_expr    = $opt->{output};
    my $re             = $opt->{regex};

    my @line_parts;

    if($print_filename) {
        if( $heading ) {
            push @line_parts, $line_no;
        }
        else {
            push @line_parts, $filename, $line_no;
        }

        if( $print_column ) {
            push @line_parts, get_match_column();
        }
    }
    if( $output_expr ) {
        # XXX avoid re-evaluation if we can
        while( $line =~ /$re/g ) {
            my $output = eval qq{"$output_expr"};
            App::Ack::print( join( $separator, @line_parts, $output ), $ors );
        }
    }
    else {
        push @line_parts, $line;
        App::Ack::print( join( $separator, @line_parts ), $ors );
    }

    return;
}

{

my $is_first_match;
my $previous_file_processed;
my $previous_line_printed;

BEGIN {
    $is_first_match        = 1;
    $previous_line_printed = -1;
}

sub print_line_with_context {
    my ( $opt, $filename, $matching_line, $line_no ) = @_;

    my $heading = $opt->{heading};

    if( !defined($previous_file_processed) ||
      $previous_file_processed ne $filename ) {
        $previous_file_processed = $filename;
        $previous_line_printed   = -1;

        if( $heading ) {
            $is_first_match = 1;
        }
    }

    my $ors                 = $opt->{print0} ? "\0" : "\n";
    my $color               = $opt->{color};
    my $match_word          = $opt->{w};
    my $re                  = $opt->{regex};
    my $is_tracking_context = $opt->{after_context} || $opt->{before_context};
    my $output_expr         = $opt->{output};

    chomp $matching_line;

    my ( $before_context, $after_context ) = get_context();

    if($before_context) {
        my $first_line = $. - @{$before_context};
        if( !$is_first_match && $previous_line_printed != $first_line - 1 ) {
            App::Ack::print('--', $ors);
        }
        $previous_line_printed = $.; # XXX unless --after-context
        my $offset = @{$before_context};
        foreach my $line (@{$before_context}) {
            chomp $line;
            App::Ack::print_line_with_options($opt, $filename, $line, $. - $offset, '-');
            $previous_line_printed = $. - $offset;
            $offset--;
        }
    }

    if( $is_tracking_context && !$is_first_match && $previous_line_printed != $. - 1 ) {
        App::Ack::print('--', $ors);
    }

    if($color) {
        $filename = Term::ANSIColor::colored($filename,
            $ENV{ACK_COLOR_FILENAME});
        $line_no  = Term::ANSIColor::colored($line_no,
            $ENV{ACK_COLOR_LINENO});
    }

    my @capture_indices  = get_capture_indices();
    if( @capture_indices && !$output_expr ) {
        my $offset = 0; # additional offset for when we add stuff

        foreach my $index_pair ( @capture_indices ) {
            my ( $match_start, $match_end ) = @{$index_pair};

            my $substring = substr( $matching_line,
                $offset + $match_start, $match_end - $match_start );
            my $substitution = Term::ANSIColor::colored( $substring,
                $ENV{ACK_COLOR_MATCH} );

            substr( $matching_line, $offset + $match_start,
                $match_end - $match_start, $substitution );

            $offset += length( $substitution ) - length( $substring );
        }
    }
    elsif($color) {
        # XXX I know $& is a no-no; fix it later
        $matching_line  =~ s/$re/Term::ANSIColor::colored($&, $ENV{ACK_COLOR_MATCH})/ge;
        $matching_line .= "\033[0m\033[K";
    }

    App::Ack::print_line_with_options($opt, $filename, $matching_line, $line_no, ':');
    $previous_line_printed = $.;

    if($after_context) {
        my $offset = 1;
        foreach my $line (@{$after_context}) {
            chomp $line;
            App::Ack::print_line_with_options($opt, $filename, $line, $. + $offset, '-');
            $previous_line_printed = $. + $offset;
            $offset++;
        }
    }

    $is_first_match = 0;
}

}

# inefficient, but functional
sub filetypes {
    my ( $resource ) = @_;

    my @matches;

    foreach my $k (keys %mappings) {
        my $filters = $mappings{$k};

        foreach my $filter (@{$filters}) {
            # clone the resource
            my $clone = $resource->clone;
            if ( $filter->filter($clone) ) {
                push @matches, $k;
                last;
            }
        }
    }

    return sort @matches;
}



1; # End of App::Ack
package App::Ack::Resource;


use warnings;
use strict;
use overload
    '""' => 'name';

sub FAIL {
    require Carp;
    Carp::confess( 'Must be overloaded' );
}


sub new {
    return FAIL();
}


sub name {
    return FAIL();
}


sub is_binary {
    return FAIL();
}



sub needs_line_scan {
    return FAIL();
}


sub reset {
    return FAIL();
}


sub next_text {
    return FAIL();
}


sub close {
    return FAIL();
}


sub clone {
    return FAIL();
}

1;
package App::Ack::Resources;



use warnings;
use strict;


sub from_argv {
    my $class = shift;
    my $opt   = shift;
    my $start = shift;

    my $self = bless {}, $class;

    my $file_filter    = undef;
    my $descend_filter = undef;

    $self->{iter} =
        File::Next::files( {
            file_filter     => $opt->{file_filter},
            descend_filter  => $opt->{descend_filter},
            error_handler   => sub { my $msg = shift; App::Ack::warn( $msg ) },
            sort_files      => $opt->{sort_files},
            follow_symlinks => $opt->{follow},
        }, @{$start} );

    return $self;
}


sub from_file {
    my $class = shift;
    my $opt   = shift;
    my $file  = shift;

    my $iter =
        File::Next::from_file( {
            error_handler   => sub { my $msg = shift; App::Ack::warn( $msg ) },
            warning_handler => sub { my $msg = shift; App::Ack::warn( $msg ) },
            sort_files      => $opt->{sort_files},
        }, $file ) or return undef;

    return bless {
        iter => $iter,
    }, $class;
}

# This is for reading input lines from STDIN, not the list of files from STDIN
sub from_stdin {
    my $class = shift;
    my $opt   = shift;

    my $self  = bless {}, $class;

    my $has_been_called = 0;

    $self->{iter} = sub {
        if ( !$has_been_called ) {
            $has_been_called = 1;
            return '-';
        }
        return;
    };

    return $self;
}

sub next {
    my $self = shift;

    my $file = $self->{iter}->() or return;

    return App::Ack::Resource::Basic->new( $file );
}

1;
package App::Ack::Resource::Basic;


use warnings;
use strict;

BEGIN {
    our @ISA = 'App::Ack::Resource';
}


sub new {
    my $class    = shift;
    my $filename = shift;

    my $self = bless {
        filename => $filename,
        fh       => undef,
        opened   => undef,
    }, $class;

    if ( $self->{filename} eq '-' ) {
        $self->{fh} = *STDIN;
    }
    else {
        if ( !open( $self->{fh}, '<', $self->{filename} ) ) {
            App::Ack::warn( "$self->{filename}: $!" );
            return;
        }
    }

    return $self;
}


sub name {
    my $self = shift;

    return $self->{filename};
}



sub needs_line_scan {
    my $self  = shift;
    my $opt   = shift;

    return 1 if $opt->{v};

    my $size = -s $self->{fh};
    if ( $size == 0 ) {
        return 0;
    }
    elsif ( $size > 100_000 ) {
        return 1;
    }

    my $buffer;
    my $rc = sysread( $self->{fh}, $buffer, $size );
    if ( not defined $rc ) {
        App::Ack::warn( "$self->{filename}: $!" );
        return 1;
    }
    return 0 unless $rc && ( $rc == $size );

    my $regex = $opt->{regex};
    return $buffer =~ /$regex/m;
}


sub reset {
    my $self = shift;

    seek( $self->{fh}, 0, 0 )
        or App::Ack::warn( "$self->{filename}: $!" );

    return;
}


sub next_text {
    if ( defined ($_ = readline $_[0]->{fh}) ) {
        $. = ++$_[0]->{line};
        return 1;
    }

    return;
}


sub close {
    my $self = shift;

    if ( not close $self->{fh} ) {
        App::Ack::warn( $self->name() . ": $!" );
    }

    return;
}


sub clone {
    my ( $self ) = @_;

    return __PACKAGE__->new($self->name);
}


1;
package App::Ack::Filter;

use strict;
use warnings;
use overload
    '""' => 'to_string';

use Carp ();

my %filter_types;


sub create_filter {
    my ( undef, $type, @args ) = @_;

    if ( my $package = $filter_types{$type} ) {
        return $package->new(@args);
    }
    Carp::croak "Unknown filter type '$type'";
}


sub register_filter {
    my ( undef, $type, $package ) = @_;

    $filter_types{$type} = $package;

    return;
}


sub invert {
    my ( $self ) = @_;

    return App::Ack::Filter::Inverse->new( $self );
}


sub is_inverted {
    return 0;
}


sub to_string {
    my ( $self ) = @_;

    return "(unimplemented to_string)";
}


sub inspect {
    my ( $self ) = @_;

    return ref($self);
}

1;
package App::Ack::Filter::Extension;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

sub new {
    my ( $class, @extensions ) = @_;

    my $exts = join('|', map { "\Q$_\E"} @extensions);
    my $re   = qr/[.](?:$exts)$/i;

    return bless {
        extensions => \@extensions,
        regex      => $re,
    }, $class;
};

sub filter {
    my ( $self, $resource ) = @_;

    my $re = $self->{'regex'};

    return $resource->name =~ /$re/;
}

sub inspect {
    my ( $self ) = @_;

    my $re = $self->{'regex'};

    return ref($self) . " - $re";
}

sub to_string {
    my ( $self ) = @_;

    my $exts = $self->{'extensions'};

    return join(' ', map { ".$_" } @{$exts});
}

BEGIN {
    App::Ack::Filter->register_filter(ext => __PACKAGE__);
}

1;
package App::Ack::Filter::FirstLineMatch;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

sub new {
    my ( $class, $re ) = @_;

    $re =~ s{^/|/$}{}g; # XXX validate?
    $re = qr{$re}i;

    return bless {
        regex => $re,
    }, $class;
}

# XXX This test checks the first "line" of the file, but we need
# it to be less piggy.  If it's something like a .min.js file, then
# the "line" could be the entire file.  Instead, it should read the
# first, say, 100 characters of the first line.

sub filter {
    my ( $self, $resource ) = @_;

    my $re = $self->{'regex'};

    local $_;
    return unless $resource->next_text;

    return /$re/;
}

sub inspect {
    my ( $self ) = @_;

    my $re = $self->{'regex'};

    return ref($self) . " - $re";
}

sub to_string {
    my ( $self ) = @_;

    my $re = $self->{'regex'};

    return "first line matches $re";
}

BEGIN {
    App::Ack::Filter->register_filter(firstlinematch => __PACKAGE__);
}

1;
package App::Ack::Filter::Is;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

use File::Spec ();

sub new {
    my ( $class, $filename ) = @_;

    return bless {
        filename => $filename,
    }, $class;
}

sub filter {
    my ( $self, $resource ) = @_;

    my $filename = $self->{'filename'};
    my $base     = (File::Spec->splitpath($resource->name))[2];

    return $base eq $filename;
}

sub inspect {
    my ( $self ) = @_;

    my $filename = $self->{'filename'};

    return ref($self) . " - $filename";
}

sub to_string {
    my ( $self ) = @_;

    my $filename = $self->{'filename'};
}

BEGIN {
    App::Ack::Filter->register_filter(is => __PACKAGE__);
}

1;
package App::Ack::Filter::Match;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

use File::Spec;

sub new {
    my ( $class, $re ) = @_;

    $re =~ s{^/|/$}{}g; # XXX validate?
    $re = qr/$re/i;

    return bless {
        regex => $re,
    }, $class;
}

sub filter {
    my ( $self, $resource ) = @_;

    my $re   = $self->{'regex'};
    my $base = (File::Spec->splitpath($resource->name))[2];

    return $base =~ /$re/;
}

sub inspect {
    my ( $self ) = @_;

    my $re = $self->{'regex'};

    print ref($self) . " - $re";
}

sub to_string {
    my ( $self ) = @_;

    my $re = $self->{'regex'};

    return "filename matches $re";
}

BEGIN {
    App::Ack::Filter->register_filter(match => __PACKAGE__);
}

1;
package App::Ack::Filter::Default;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

sub new {
    my ( $class ) = @_;

    return bless {}, $class;
}

sub filter {
    my ( $self, $resource ) = @_;

    return -T $resource->name;
}

1;
package App::Ack::Filter::Inverse;

use strict;
use warnings;
BEGIN {
    our @ISA = 'App::Ack::Filter';
}

sub new {
    my ( $class, $filter ) = @_;

    return bless {
        filter => $filter,
    }, $class;
}

sub filter {
    my ( $self, $resource ) = @_;

    my $filter = $self->{'filter'};
    return !$filter->filter( $resource );
}

sub invert {
    my $self = shift;

    return $self->{'filter'};
}

sub is_inverted {
    return 1;
}

sub inspect {
    my ( $self ) = @_;

    my $filter = $self->{'filter'};

    return "!$filter";
}

1;
package App::Ack::ConfigFinder;


use strict;
use warnings;

use Cwd ();
use File::Spec;

BEGIN {
    if($App::Ack::is_windows) {
        require Win32;
    };
}


sub new {
    my ( $class ) = @_;

    return bless {}, $class;
}

sub _remove_redundancies {
    my ( @configs ) = @_;

    my %dev_and_inode_seen;

    foreach my $path ( @configs ) {
        my ( $dev, $inode ) = (stat $path)[0, 1];

        if( defined( $dev ) ) { # files that can't be read don't matter
            if( $dev_and_inode_seen{"$dev:$inode"} ) {
                undef $path;
            } else {
                $dev_and_inode_seen{"$dev:$inode"} = 1;
            }
        }
    }
    return grep { defined() } @configs;
}


sub find_config_files {
    my @config_files;

    if($App::Ack::is_windows) {
        no strict 'subs';
        push @config_files, map { File::Spec->catfile($_, 'ackrc') } (
            Win32::GetFolderPath(Win32::CSIDL_COMMON_APPDATA),
            Win32::GetFolderPath(Win32::CSIDL_APPDATA),
        );
        if(defined(my $home = $ENV{'HOME'})) {
            push @config_files, File::Spec->catfile($home, '_ackrc');
        }
    } else {
        push @config_files, '/etc/ackrc';
        if(defined(my $home = $ENV{'HOME'})) {
            push @config_files, File::Spec->catfile($home, '.ackrc');
        }
    }

    my @dirs = File::Spec->splitdir(Cwd::getcwd());
    while(@dirs) {
        my $ackrc = File::Spec->catfile(@dirs, '.ackrc');
        if(-f $ackrc) {
            push @config_files, $ackrc;
            last;
        }
        $ackrc = File::Spec->catfile(@dirs, '_ackrc');
        if(-f $ackrc) {
            push @config_files, $ackrc;
            last;
        }
        pop @dirs;
    }

    return _remove_redundancies( @config_files );
}

1;
package App::Ack::ConfigLoader;

use strict;
use warnings;

use Carp ();
use Getopt::Long; # Must be 2.36, but we can't check for that in the use.
use Text::ParseWords ();


sub process_filter_spec {
    my ( $spec ) = @_;

    if ( $spec =~ /^(\w+):(\w+):(.*)/ ) {
        my ( $type_name, $ext_type, $arguments ) = ( $1, $2, $3 );

        return ( $type_name,
            App::Ack::Filter->create_filter($ext_type, split(/,/, $arguments)) );
    }
    elsif ( $spec =~ /^(\w+)=(.*)/ ) { # Check to see if we have ack1-style argument specification.
        my ( $type_name, $extensions ) = ( $1, $2 );

        my @extensions = split(/,/, $extensions);
        foreach my $extension ( @extensions ) {
            $extension =~ s/^[.]//;
        }

        return ( $type_name, App::Ack::Filter->create_filter('ext', @extensions) );
    }
    else {
        Carp::croak "invalid filter specification '$spec'";
    }
}

sub process_filetypes {
    my ( $opt, $arg_sources ) = @_;

    Getopt::Long::Configure('default'); # start with default options
    Getopt::Long::Configure(
        'no_ignore_case',
        'no_auto_abbrev',
        'pass_through',
    );
    my %additional_specs;

    my $add_spec = sub {
        my ( undef, $spec ) = @_;

        my ( $name, $filter ) = process_filter_spec($spec);

        push @{ $App::Ack::mappings{$name} }, $filter;

        $additional_specs{$name . '!'} = sub {
            my ( undef, $value ) = @_;

            my @filters = @{ $App::Ack::mappings{$name} };
            if ( not $value ) {
                @filters = map { $_->invert() } @filters;
            }

            push @{ $opt->{'filters'} }, @filters;
        };
    };

    my $set_spec = sub {
        my ( undef, $spec ) = @_;

        my ( $name, $filter ) = process_filter_spec($spec);

        $App::Ack::mappings{$name} = [ $filter ];

        $additional_specs{$name . '!'} = sub {
            my ( undef, $value ) = @_;

            my @filters = @{ $App::Ack::mappings{$name} };
            if ( not $value ) {
                @filters = map { $_->invert() } @filters;
            }

            push @{ $opt->{'filters'} }, @filters;
        };
    };

    my %type_arg_specs = (
        'type-add=s' => $add_spec,
        'type-set=s' => $set_spec,
    );

    for ( my $i = 0; $i < @{$arg_sources}; $i += 2) {
        my ( $source_name, $args ) = @{$arg_sources}[ $i, $i + 1];

        if ( ref($args) ) {
            # $args are modified in place, so no need to munge $arg_sources
            Getopt::Long::GetOptionsFromArray($args, %type_arg_specs);
        }
        else {
            ( undef, $arg_sources->[$i + 1] ) =
                Getopt::Long::GetOptionsFromString($args, %type_arg_specs);
        }
    }

    $additional_specs{'known-types'} = sub {
        my ( undef, $value ) = @_;

        my @filters = map { @$_ } values(%App::Ack::mappings);

        push @{ $opt->{'filters'} }, @filters;
    };

    return \%additional_specs;
}

sub get_arg_spec {
    my ( $opt, $extra_specs ) = @_;

    return {
        1                   => sub { $opt->{1} = $opt->{m} = 1 },
        'A|after-context=i' => \$opt->{after_context},
        'B|before-context=i'
                            => \$opt->{before_context},
        'C|context:i'       => sub { shift; my $val = shift; $opt->{before_context} = $opt->{after_context} = ($val || 2) },
        'a|all-types'       => \$opt->{all},
        'break!'            => \$opt->{break},
        c                   => \$opt->{count},
        'color|colour!'     => \$opt->{color},
        'color-match=s'     => \$ENV{ACK_COLOR_MATCH},
        'color-filename=s'  => \$ENV{ACK_COLOR_FILENAME},
        'color-lineno=s'    => \$ENV{ACK_COLOR_LINENO},
        'column!'           => \$opt->{column},
        count               => \$opt->{count},
        'env!'              => sub {
            my ( undef, $value ) = @_;

            if ( !$value ) {
                $opt->{noenv_seen} = 1;
            }
        },
        f                   => \$opt->{f},
        'files-from=s'      => \$opt->{files_from},
        'filter!'           => \$App::Ack::is_filter_mode,
        flush               => \$opt->{flush},
        'follow!'           => \$opt->{follow},
        g                   => \$opt->{g},
        'group!'            => sub { shift; $opt->{heading} = $opt->{break} = shift },
        'heading!'          => \$opt->{heading},
        'h|no-filename'     => \$opt->{h},
        'H|with-filename'   => \$opt->{H},
        'i|ignore-case'     => \$opt->{i},
        'ignore-directory|ignore-dir=s' # XXX Combine this version with the negated version below
                            => sub {
                                my ( undef, $dir ) = @_;

                                $dir = App::Ack::remove_dir_sep( $dir );
                                if ( $dir !~ /^(?:is|match):/ ) {
                                    $dir = 'is:' . $dir;
                                }
                                push @{ $opt->{idirs} }, $dir;
                               },
        'ignore-file=s'    => sub {
                                    my ( undef, $file ) = @_;
                                    push @{ $opt->{ifiles} }, $file;
                               },
        'lines=s'           => sub { shift; my $val = shift; push @{$opt->{lines}}, $val },
        'l|files-with-matches'
                            => \$opt->{l},
        'L|files-without-matches'
                            => sub { $opt->{l} = $opt->{v} = 1 },
        'm|max-count=i'     => \$opt->{m},
        'match=s'           => \$opt->{regex},
        'n|no-recurse'      => \$opt->{n},
        o                   => sub { $opt->{output} = '$&' },
        'output=s'          => \$opt->{output},
        'pager=s'           => \$opt->{pager},
        'noignore-directory|noignore-dir=s'
                            => sub {
                                my ( undef, $dir ) = @_;

                                # XXX can you do --noignore-dir=match,...?
                                $dir = App::Ack::remove_dir_sep( $dir );
                                if ( $dir !~ /^(?:is|match):/ ) {
                                    $dir = 'is:' . $dir;
                                }
                                if ( $dir !~ /^(?:is|match):/ ) {
                                    Carp::croak("invalid noignore-directory argument: '$dir'");
                                }

                                @{ $opt->{idirs} } = grep {
                                    $_ ne $dir
                                } @{ $opt->{idirs} };
                               },
        'nopager'           => sub { $opt->{pager} = undef },
        'passthru'          => \$opt->{passthru},
        'print0'            => \$opt->{print0},
        'Q|literal'         => \$opt->{Q},
        'r|R|recurse'       => sub { $opt->{n} = 0 },
        'show-types'        => \$opt->{show_types},
        'smart-case!'       => \$opt->{smart_case},
        'sort-files'        => \$opt->{sort_files},
        'type=s'            => sub {
            my ( $getopt, $value ) = @_;

            my $cb_value = 1;
            if ( $value =~ s/^no// ) {
                $cb_value = 0;
            }

            my $callback = $extra_specs->{ $value . '!' };

            if ( $callback ) {
                $callback->( $getopt, $cb_value );
            }
            else {
                Carp::croak( "Unknown type '$value'" );
            }
        },
        'u|unrestricted'    => \$opt->{u},
        'v|invert-match'    => \$opt->{v},
        'w|word-regexp'     => \$opt->{w},
        'x'                 => sub { $opt->{files_from} = '-' },

        'version'           => sub { App::Ack::print_version_statement(); exit; },
        'help|?:s'          => sub { shift; App::Ack::show_help(@_); exit; },
        'help-types'        => sub { App::Ack::show_help_types(); exit; },
        'man'               => sub {
            require Pod::Usage;
            Pod::Usage::pod2usage({
                -verbose => 2,
                -exitval => 0,
            });
        }, # man sub
        $extra_specs ? %{$extra_specs} : (),
    }; # arg_specs
}

sub process_other {
    my ( $opt, $extra_specs, $arg_sources ) = @_;

    Getopt::Long::Configure('default'); # start with default options
    Getopt::Long::Configure(
        'bundling',
        'no_ignore_case',
    );

    my $arg_specs = get_arg_spec($opt, $extra_specs);

    for ( my $i = 0; $i < @{$arg_sources}; $i += 2) {
        my ($source_name, $args) = @{$arg_sources}[$i, $i + 1];

        my $ret;
        if ( ref($args) ) {
            $ret = Getopt::Long::GetOptionsFromArray( $args, %{$arg_specs} );
        }
        else {
            ( $ret, $arg_sources->[$i + 1] ) =
                Getopt::Long::GetOptionsFromString( $args, %{$arg_specs} );
        }
        if ( !$ret ) {
            my $where = $source_name eq 'ARGV' ? 'on command line' : "in $source_name";
            App::Ack::die( "Invalid option $where" );
        }
        if ( $opt->{noenv_seen} ) {
            App::Ack::die( "--noenv found in $source_name" );
        }
    }

    # XXX We need to check on a -- in the middle of a non-ARGV source

    return;
}

sub should_dump_options {
    my ( $sources ) = @_;

    for(my $i = 0; $i < @{$sources}; $i += 2) {
        my ( $name, $options ) = @{$sources}[$i, $i + 1];
        if($name eq 'ARGV') {
            my $dump;
            Getopt::Long::Configure('default', 'pass_through');
            Getopt::Long::GetOptionsFromArray($options,
                'dump' => \$dump,
            );
            return $dump;
        }
    }
    return;
}

sub explode_sources {
    my ( $sources ) = @_;

    my @new_sources;

    Getopt::Long::Configure('default', 'pass_through');

    my %opt;
    my $arg_spec = get_arg_spec(\%opt);

    my $add_type = sub {
        my ( undef, $arg ) = @_;

        # XXX refactor?
        if ( $arg =~ /(\w+)=/) {
            $arg_spec->{$1} = sub {};
        } else {
            ( $arg ) = split /:/, $arg;
            $arg_spec->{$arg} = sub {};
        }
    };

    for(my $i = 0; $i < @{$sources}; $i += 2) {
        my ( $name, $options ) = @{$sources}[$i, $i + 1];
        if ( ref($options) ne 'ARRAY' ) {
            $sources->[$i + 1] = $options =
                [ Text::ParseWords::shellwords($options) ];
        }
        for ( my $j = 0; $j < @{$options}; $j++ ) {
            next unless $options->[$j] =~ /^-/;
            my @chunk = ( $options->[$j] );
            push @chunk, $options->[$j] while ++$j < @{$options} && $options->[$j] !~ /^-/;
            $j--;

            my @copy = @chunk;
            Getopt::Long::GetOptionsFromArray(\@chunk,
                'type-add=s' => $add_type,
                'type-set=s' => $add_type,
            );
            Getopt::Long::GetOptionsFromArray(\@chunk, %{$arg_spec});

            splice @copy, -1 * @chunk if @chunk; # XXX explain this
            push @new_sources, $name, \@copy;
        }
    }

    return \@new_sources;
}

sub compare_opts {
    my ( $a, $b ) = @_;

    my $first_a = $a->[0];
    my $first_b = $b->[0];

    $first_a =~ s/^--?//;
    $first_b =~ s/^--?//;

    return $first_a cmp $first_b;
}

sub dump_options {
    my ( $sources ) = @_;

    $sources = explode_sources($sources);

    my %opts_by_source;
    my @source_names;

    for(my $i = 0; $i < @{$sources}; $i += 2) {
        my ( $name, $contents ) = @{$sources}[$i, $i + 1];
        if ( not $opts_by_source{$name} ) {
            $opts_by_source{$name} = [];
            push @source_names, $name;
        }
        push @{$opts_by_source{$name}}, $contents;
    }

    foreach my $name (@source_names) {
        my $contents = $opts_by_source{$name};

        print $name, "\n";
        print '=' x length($name), "\n";
        print '  ', join(' ', @{$_}), "\n" foreach sort { compare_opts($a, $b) } @{$contents};
    }

    return;
}

sub remove_default_options_if_needed {
    my ( $sources ) = @_;

    my $default_index;

    foreach my $index ( 0 .. $#$sources ) {
        if ( $sources->[$index] eq 'Defaults' ) {
            $default_index = $index;
            last;
        }
    }

    return $sources unless defined $default_index;

    my $should_remove = 0;

    Getopt::Long::Configure('default'); # start with default options
    Getopt::Long::Configure(
        'no_ignore_case',
        'no_auto_abbrev',
        'pass_through',
    );

    foreach my $index ( $default_index + 2 .. $#$sources ) {
        next if $index % 2 != 0;

        my ( $name, $args ) = @{$sources}[ $index, $index + 1 ];

        if(ref($args)) {
            Getopt::Long::GetOptionsFromArray($args,
                'ignore-ack-defaults' => \$should_remove,
            );
        } else {
            ( undef, $sources->[$index + 1] ) = Getopt::Long::GetOptionsFromString($args,
                'ignore-ack-defaults' => \$should_remove,
            );
        }
    }

    Getopt::Long::Configure('default');

    return $sources unless $should_remove;

    my @copy = @{$sources};
    splice @copy, $default_index, 2;
    return \@copy;
}

sub process_args {
    my $arg_sources = \@_;

    my %opt;

    $arg_sources = remove_default_options_if_needed($arg_sources);

    if ( should_dump_options($arg_sources) ) {
        dump_options($arg_sources);
        exit(0);
    }

    my $type_specs = process_filetypes(\%opt, $arg_sources);
    process_other(\%opt, $type_specs, $arg_sources);
    while ( @{$arg_sources} ) {
        my ( $source_name, $args ) = splice( @{$arg_sources}, 0, 2 );

        # All of our sources should be transformed into an array ref
        if ( ref($args) ) {
            if ( $source_name eq 'ARGV' ) {
                @ARGV = @{$args};
            }
            elsif (@{$args}) {
                Carp::croak "source '$source_name' has extra arguments!";
            }
        }
        else {
            Carp::croak 'The impossible has occurred!';
        }
    }
    my $filters = ($opt{filters} ||= []);

    # throw the default filter in if no others are selected
    if ( not grep { !$_->is_inverted() } @{$filters} ) {
        push @{$filters}, App::Ack::Filter::Default->new();
    }
    return \%opt;
}

1; # End of App::Ack::ConfigLoader
package App::Ack::ConfigDefault;

use warnings;
use strict;

sub options {
    my @options = split( /\n/, _options_block() );
    @options = grep { /./ && !/^#/ } @options;

    return @options;
}

sub _options_block {
    return <<'HERE';
# This is the default ackrc for ack 2.0

# There are four different ways to match
# is:  Match the filename exactly
# ext: Match the extension of the filename exactly
# match: Match the filename against a Perl regular expression
# firstlinematch: Match the first 80 characters of the first line
#   of text against a Perl regular expression.  This is only for
#   the --type-add option.


# Directories to ignore
# Bazaar
--ignore-directory=is:.bzr

# Codeville
--ignore-directory=is:.cdv

# Interface Builder
--ignore-directory=is:~.dep
--ignore-directory=is:~.dot
--ignore-directory=is:~.nib
--ignore-directory=is:~.plst

# Git
--ignore-directory=is:.git

# Mercurial
--ignore-directory=is:.hg

# quilt
--ignore-directory=is:.pc

# Subversion
--ignore-directory=is:.svn

# Monotone
--ignore-directory=is:_MTN

# CVS
--ignore-directory=is:CVS

# RCS
--ignore-directory=is:RCS

# SCCS
--ignore-directory=is:SCCS

# darcs
--ignore-directory=is:_darcs

# Vault/Fortress
--ignore-directory=is:_sgbak

# autoconf
--ignore-directory=is:autom4te.cache

# Perl module building
--ignore-directory=is:blib
--ignore-directory=is:_build

# Perl Devel::Cover module's output directory
--ignore-directory=is:cover_db



# Files to ignore
# Backup files
--ignore-file=ext:bak
--ignore-file=match:/~$/

# Emacs swap files
--ignore-file=match:/^#.+#$/

# vi/vim swap files
--ignore-file=match:/[._].*\.swp$/

# core dumps
--ignore-file=match:/core\.\d+$/

# minified Javascript
--ignore-file=match:/[.]min[.]js$/


# Filetypes defined

# Perl http://perl.org/
--type-add=perl:ext:pl,pm,pod,t
--type-add=perl:firstlinematch:/#!.*\bperl/

# Makefiles http://www.gnu.org/s/make/
--type-add=make:ext:mk
--type-add=make:ext:mak
--type-add=make:is:makefile
--type-add=make:is:Makefile
--type-add=make:is:GNUmakefile

# Rakefiles http://rake.rubyforge.org/
--type-add=rake:is:Rakefile

# CMake http://www.cmake.org/
--type-add=cmake:is:CMakeLists.txt
--type-add=cmake:ext:cmake

# Actionscript
--type-add=actionscript:ext:as,mxml

# Ada http://www.adaic.org/
--type-add=ada:ext:ada,adb,ads

# Assembly
--type-add=asm:ext:asm,s

# Batch
--type-add=batch:ext:bat,cmd

# ColdFusion http://en.wikipedia.org/wiki/ColdFusion
--type-add=cfmx:ext:cfc,cfm,cfml

# Clojure http://clojure.org/
--type-add=clojure:ext:clj

# C
# .xs are Perl C files
--type-add=cc:ext:c,h,xs

# C header files
--type-add=hh:ext:h

# C++
--type-add=cpp:ext:cpp,cc,cxx,m,hpp,hh,h,hxx

# C#
--type-add=csharp:ext:cs

# CSS http://www.w3.org/Style/CSS/
--type-add=css:ext:css

# Delphi http://en.wikipedia.org/wiki/Embarcadero_Delphi
--type-add=delphi:ext:pas,int,dfm,nfm,dof,dpk,dproj,groupproj,bdsgroup,bdsproj

# Emacs Lisp http://www.gnu.org/software/emacs
--type-add=elisp:ext:el

# Erlang http://www.erlang.org/
--type-add=erlang:ext:erl,hrl

# Fortran http://en.wikipedia.org/wiki/Fortran
--type-add=fortran:ext:f,f77,f90,f95,f03,for,ftn,fpp

# Google Go http://golang.org/
--type-add=go:ext:go

# Groovy http://groovy.codehaus.org/
--type-add=groovy:ext:groovy,gtmpl,gpp,grunit

# Haskell http://www.haskell.org/
--type-add=haskell:ext:hs,lhs

# HTML
--type-add=html:ext:htm,html

# Java http://www.oracle.com/technetwork/java/index.html
--type-add=java:ext:java,properties

# JavaScript
--type-add=js:ext:js

# JSP http://www.oracle.com/technetwork/java/javaee/jsp/index.html
--type-add=jsp:ext:jsp,jspx,jhtm,jhtml

# Common Lisp http://common-lisp.net/
--type-add=lisp:ext:lisp,lsp

# Lua http://www.lua.org/
--type-add=lua:ext:lua

# Objective-C
--type-add=objc:ext:m,h

# Objective-C++
--type-add=objcpp:ext:mm,h

# OCaml http://caml.inria.fr/
--type-add=ocaml:ext:ml,mli

# Parrot http://www.parrot.org/
--type-add=parrot:ext:pir,pasm,pmc,ops,pod,pg,tg

# PHP http://www.php.net/
--type-add=php:ext:php,phpt,php3,php4,php5,phtml
--type-add=php:firstlinematch:/#!.*\bphp/

# Plone http://plone.org/
--type-add=plone:ext:pt,cpt,metadata,cpy,py

# Python http://www.python.org/
--type-add=python:ext:py
--type-add=python:firstlinematch:/#!.*\bpython/

# R http://www.r-project.org/
--type-add=rr:ext:R

# Ruby http://www.ruby-lang.org/
--type-add=ruby:ext:rb,rhtml,rjs,rxml,erb,rake,spec
--type-add=ruby:is:Rakefile
--type-add=ruby:firstlinematch:/#!.*\bruby/

# Scala http://www.scala-lang.org/
--type-add=scala:ext:scala

# Scheme http://groups.csail.mit.edu/mac/projects/scheme/
--type-add=scheme:ext:scm,ss

# Shell
--type-add=shell:ext:sh,bash,csh,tcsh,ksh,zsh
--type-add=shell:firstlinematch:/(?:ba|t?c|k|z)?sh\b/

# Smalltalk http://www.smalltalk.org/
--type-add=smalltalk:ext:st

# SQL http://www.iso.org/iso/catalogue_detail.htm?csnumber=45498
--type-add=sql:ext:sql,ctl

# Tcl http://www.tcl.tk/
--type-add=tcl:ext:tcl,itcl,itk

# LaTeX http://www.latex-project.org/
--type-add=tex:ext:tex,cls,sty

# Template Toolkit http://template-toolkit.org/
--type-add=tt:ext:tt,tt2,ttml

# Visual Basic
--type-add=vb:ext:bas,cls,frm,ctl,vb,resx

# Verilog
--type-add=verilog:ext:v,vh,sv

# VHDL http://www.eda.org/twiki/bin/view.cgi/P1076/WebHome
--type-add=vhdl:ext:vhd,vhdl

# Vim http://www.vim.org/
--type-add=vim:ext:vim

# XML http://www.w3.org/TR/REC-xml/
--type-add=xml:ext:xml,dtd,xsl,xslt,ent
--type-add=xml:firstlinematch:/<[?]xml/

# YAML http://yaml.org/
--type-add=yaml:ext:yaml,yml
HERE
}

1;