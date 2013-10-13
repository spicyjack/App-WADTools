#!/usr/bin/perl -w

use strict;
use warnings;

our @copyright = (
    q|Copyright (c) 2013 by Brian Manning |,
    q|<brian at xaoc dot org>|
);

# For support with this file, please file an issue on the GitHub issue tracker
# for this project: https://github.com/spicyjack/App-WADTools/issues

=head1 NAME

B<wadindex.pl> - Create an index of WAD files


=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

 perl wadindex.pl [OPTIONS]

 Script options:
 -v|--verbose       Verbose script execution
 -d|--debug         Debug script execution (tons of output)
 -h|--help          Shows this help text
 -c|--colorize      Always colorize script output

 -p|--path          Path to WAD files/directories with WAD files
 -t|--tempdir       Temporary directory to use when unzipping WAD files

 Example usage:

 # list the structure of an XLS file
 wadindex.pl --path /path/to/wad/files --tempdir /dev/shm

You can view the full C<POD> documentation of this file by calling C<perldoc
wadindex.pl>.

=cut

our @options = (
    # script options
    q(debug|d),
    q(verbose|v),
    q(help|h),
    q(colorize|c), # always colorize output
    # other options

    q(path|p=s),
    q(tempdir|t=s),
);

=head1 DESCRIPTION

Given a directory with WAD files (or WAD files zipped up
inside of '.zip' files), create an index that contains:

=over

=item The name of the WAD file

=item What levels that WAD file contains

=item The WAD's author

=item The WAD's checksum

=item The WAD's average rating on Doomworld

=back

=head1 OBJECTS

=head2 WADIndex::Config

An object used for storing configuration data.

=head3 Object Methods

=cut

####################
# WADIndex::Config #
####################
package WADIndex::Config;
use strict;
use warnings;
use Getopt::Long;
use Log::Log4perl;
use Pod::Usage;
use POSIX qw(strftime);

=over

=item new( )

Creates the L<WADIndex::Config> object, and parses out options using
L<Getopt::Long>.

=cut

sub new {
    my $class = shift;

    my $self = bless ({}, $class);

    # script arguments
    my %args;

    # parse the command line arguments (if any)
    my $parser = Getopt::Long::Parser->new();

    # pass in a reference to the args hash as the first argument
    $parser->getoptions( \%args, @options );

    # assign the args hash to this object so it can be reused later on
    $self->{_args} = \%args;

    # dump and bail if we get called with --help
    if ( $self->get(q(help)) ) { pod2usage(-exitstatus => 1); }

    # return this object to the caller
    return $self;
}

=item get($key)

Returns the scalar value of the key passed in as C<key>, or C<undef> if the
key does not exist in the L<WADIndex::Config> object.

=cut

sub get {
    my $self = shift;
    my $key = shift;
    # turn the args reference back into a hash with a copy
    my %args = %{$self->{_args}};

    if ( exists $args{$key} ) { return $args{$key}; }
    return undef;
}

=item set( key => $value )

Sets in the L<WADIndex::Config> object the key/value pair passed in as
arguments.  Returns the old value if the key already existed in the
L<WADIndex::Config> object, or C<undef> otherwise.

=cut

sub set {
    my $self = shift;
    my $key = shift;
    my $value = shift;
    # turn the args reference back into a hash with a copy
    my %args = %{$self->{_args}};

    if ( exists $args{$key} ) {
        my $oldvalue = $args{$key};
        $args{$key} = $value;
        $self->{_args} = \%args;
        return $oldvalue;
    } else {
        $args{$key} = $value;
        $self->{_args} = \%args;
    }
    return undef;
}

=item defined($key)

Returns "true" (C<1>) if the value for the key passed in as C<key> is
C<defined>, and "false" (C<0>) if the value is undefined, or the key doesn't
exist.

=cut

sub defined {
    my $self = shift;
    my $key = shift;
    # turn the args reference back into a hash with a copy
    my %args = %{$self->{_args}};

    # Can't use Log4perl here, since it hasn't been set up yet
    if ( exists $args{$key} ) {
        #warn qq(exists: $key\n);
        if ( defined $args{$key} ) {
            #warn qq(defined: $key; ) . $args{$key} . qq(\n);
            return 1;
        }
    }
    return 0;
}

=item get_args( )

Returns a hash containing the parsed script arguments.

=cut

sub get_args {
    my $self = shift;
    # hash-ify the return arguments
    return %{$self->{_args}};
}

=back

=head2 WADIndex::ZipTool

An object used for storing configuration data.

=head3 Object Methods

=cut

#####################
# WADIndex::ZipTool #
#####################
package WADIndex::ZipTool;
use strict;
use warnings;
use Archive::Zip qw(:ERROR_CODES);
use Log::Log4perl;

=over

=item new(zipfile => $zipfile )

Creates an C<Archive::Zip> object and processes requests for information about
the zipfile.

=cut

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless ({%args}, $class);
    my $log = Log::Log4perl->get_logger();

    my $zip = Archive::Zip->new();
    my $zipfile = $self->{filename};
    $log->debug(qq(Reading zipfile: $zipfile));
    $log->logdie(qq(Can't read zipfile $zipfile))
        unless ( $zip->read($zipfile) == AZ_OK );
    $self->{_zip} = $zip;
    $log->debug("Calling zip->members");
    my @member_objs = $zip->members();
    my @members;
    foreach my $member ( @member_objs ) {
        push(@members, $member->fileName);
    }
    $self->{_members} = \@members;
    return $self;
}

=item get_zip_members( )

Returns all of the files contained inside of the zipfile.

=cut

sub get_zip_members {
    my $self = shift;
    my $zip = $self->{_zip};
    my $log = Log::Log4perl->get_logger();

    return @{$self->{_members}};
}

=item extract_files(files => \@files)

Extracts all of the files listed in the array C<@files> from the zipfile and
returns a scalar containing the path to the temporary directory that the files
were extracted into.

=cut

sub extract_files {
    my $self = shift;
    my %args = @_;
    my $log = Log::Log4perl->get_logger();

    my $zip = $self->{_zip};
    my $cfg = $self->{cfg};

    my $dh = File::Temp->newdir(
        UNLINK      => 1,
        DIR         => $cfg->get(q(tempdir)),
        TEMPLATE    => qq(wadindex.XXXXXXXX),
    );
    $log->debug(qq(Created temp dir ) . $dh->dirname);
    foreach my $file ( @{$args{files}} ) {
        $log->debug(qq(- extracting: $file));
        my $temp_file = $dh->dirname . q(/) . $file;
        $zip->extractMemberWithoutPaths($file, $temp_file);
        $log->debug(q(- done extracting: ) . $file);
    }
    return $dh;
}

=back

=head2 WADIndex::Indexer

An object used for storing configuration data.

=head3 Object Methods

=cut

#####################
# WADIndex::Indexer #
#####################
package WADIndex::Indexer;
use strict;
use warnings;
use Data::Hexdumper;
use Fcntl qw(:seek);
use Log::Log4perl;

use constant {
    WAD_DIRECTORY_ENTRY_SIZE => 16,
    WAD_HEADER_SIZE          => 12,
};

=over

=item new( )

Parses WAD files, outputs information about the WAD file.

=cut

sub new {
    my $class = shift;
    my $self = bless ({}, $class);
    return $self;
}

=item index( )

Indexes the contents of a WAD file, and displays the information on the
screen.

=cut

sub index {
    my $self = shift;
    my %args = @_;
    my $log = Log::Log4perl->get_logger();

    $log->logdie(q(Missing 'tempdir' argument))
        unless ( defined $args{tempdir} );
    $log->logdie(q(Missing 'files' argument))
        unless ( defined $args{files} );

    foreach my $filename ( @{$args{files}} ) {
        my $wadfile = $args{tempdir} . q(/) . $filename;
        open(my $WAD, qq(<$wadfile))
            or $log->logdie(qq(Failed to open WAD file '$wadfile': $!));
        my $header;
        # read the header from the WAD file
        my $bytes_read = read( $WAD,$header, WAD_HEADER_SIZE );
        die qq(Failed to read header: $!)
            unless (defined $bytes_read);
        die qq(Only read $bytes_read bytes from header, header size is ) .
            WAD_HEADER_SIZE
            unless ( $bytes_read == WAD_HEADER_SIZE );
        my ($wad_sig,$num_lumps,$dir_offset) = unpack("a4VV",$header);
        $log->info(qq(WAD signature: $wad_sig));
        $log->info(sprintf(q(Number of lumps in the WAD:  %u lumps),
            $num_lumps));
        $log->info(sprintf(q(WAD directory start offset: +%u bytes),
            $dir_offset));
        for (my $i = 0; $i <= ($num_lumps - 1); $i++) {
            my $lump_entry;
            # reset bytes read
            $bytes_read = undef;
            # read this lump entry
            $log->info(q(Reading directory entry at offset: )
                . ($dir_offset + ( $i * WAD_DIRECTORY_ENTRY_SIZE )));
            die(qq(Can't seek WAD directory entry: $!))
                unless (seek($WAD,
                    ($dir_offset
                    + ( $i * WAD_DIRECTORY_ENTRY_SIZE )),
                    SEEK_SET));
            $bytes_read = read($WAD, $lump_entry, WAD_DIRECTORY_ENTRY_SIZE);
            die "Failed to read WAD directory entry: $!"
                unless ( defined $bytes_read );
            die qq(Only read $bytes_read out of ) . WAD_DIRECTORY_ENTRY_SIZE
                . q( bytes in header)
                unless ( $bytes_read == WAD_DIRECTORY_ENTRY_SIZE );
            my $hexdump = hexdump(
                    data => $lump_entry,
                    output_format => q(%16C::%d),
            );
            my ($hex_chars, $data) = split(/::/, $hexdump);
            $log->info(qq(lump: $data));
            $log->info(qq(lump: $hex_chars));

            my ($lump_start, $lump_size, $lump_name) = unpack(q(VVa8),
                $lump_entry );
            $lump_name =~ s/\0+//g;
            $log->info(sprintf(qq(  %0.4u name: %-8s size: %8u start: %8u),
                $i, $lump_name, $lump_size, $lump_start));
        }
        close($WAD);
    }
}

=back

=cut

################
# package main #
################
package main;
use 5.010;
use strict;
use warnings;
use utf8;

# system modules

use Carp;
use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
use Fcntl;
use File::Basename;
use File::Find::Rule;
#use File::LibMagic;
use File::Temp;
use IO::File;
use Log::Log4perl qw(get_logger :no_extra_logdie_message);
use Log::Log4perl::Level;

# FIXME change these into regexes
# WARNING: these will change depending on which 'magic' file you're looking at
use constant {
    OCTET_STREAM => q(application/octet-stream;),
    TEXT_PLAIN   => q(text/plain; charset=),
    ZIP        => q(application/zip; charset=binary),
};

    binmode(STDOUT, ":utf8");
    #my $catalog_file = q(/srv/www/purl/html/Ural_Catalog/UralCatalog.xls);
    # create a logger object
    my $cfg = WADIndex::Config->new();

    if ( ! $cfg->defined(q(tempdir)) ) {
        $cfg->set(q(tempdir), q(/dev/shm));
    }
    # set up the logger
    my $log_conf;
    if ( $cfg->defined(q(debug)) ) {
        $log_conf = qq(log4perl.rootLogger = DEBUG, Screen\n);
    } elsif ( $cfg->defined(q(verbose)) ) {
        $log_conf = qq(log4perl.rootLogger = INFO, Screen\n);
    } else {
        $log_conf = qq(log4perl.rootLogger = WARN, Screen\n);
    }

    if ( -t STDOUT || $cfg->defined(q(colorize)) ) {
        $log_conf .= qq(log4perl.appender.Screen = )
            . qq(Log::Log4perl::Appender::ScreenColoredLevels\n);
    } else {
       $log_conf .= qq(log4perl.appender.Screen = )
            . qq(Log::Log4perl::Appender::Screen\n);
    }

    $log_conf .= qq(log4perl.appender.Screen.stderr = 1\n)
        . qq(log4perl.appender.Screen.utf8 = 1\n)
        . qq(log4perl.appender.Screen.layout = PatternLayout\n)
        . q(log4perl.appender.Screen.layout.ConversionPattern )
        # %r: number of milliseconds elapsed since program start
        # %p{1}: first letter of event priority
        # %4L: line number where log statement was used, four numbers wide
        # %M{1}: Name of the method name where logging request was issued
        # %m: message
        # %n: newline
        . qq|= [%8r] %p{1} %4L (%M{1}) %m%n\n|;
        #. qq( = %d %p %m%n\n)
        #. qq(= %d{HH.mm.ss} %p -> %m%n\n);

    # create a logger object, and prime the logfile for this session
    Log::Log4perl::init( \$log_conf );
    my $log = get_logger("");

    $log->logdie(qq(Missing '--path' directory argument))
        unless ( $cfg->defined(q(path)) );
    $log->logdie(qq('--path' )
        . $cfg->get(q(path)) . q( not found/available))
        unless ( -r $cfg->get(q(path)) );

    # print a nice banner
    $log->info(qq(Starting wadindex.pl, version $VERSION));
    foreach my $c ( @copyright ) {
        $log->info($c);
    }
    $log->info(qq(My PID is $$));

    my $indexer = WADIndex::Indexer->new();
    my @files = File::Find::Rule
                        ->file
                        #->name(q(*.wad), q(*.zip))
                        ->in($cfg->get(q(path)));
    foreach my $found_file ( sort(@files) ) {
        my $filename = basename($found_file);
        $log->debug(qq(Processing file $filename));
        if ( $filename =~ /\.zip$/ ) {
            my $zipfile = WADIndex::ZipTool->new(
                cfg => $cfg,
                filename => $cfg->get(q(path)) . q(/) . $filename,
            );
            my @members = $zipfile->get_zip_members();
            my @wads_in_zip = grep(/\.wad/i, @members);
            if ( scalar(@wads_in_zip) > 0 ) {
                my $temp_dir = $zipfile->extract_files(files => \@wads_in_zip);
                my $indexer = WADIndex::Indexer->new();
                $indexer->index(tempdir => $temp_dir, files => \@wads_in_zip);
            } else {
                $log->warn(qq(No *.wad files in $zipfile));
            }
        }
    }

=head1 AUTHOR

Brian Manning, C<< <brian at xaoc dot org> >>

=head1 BUGS

Please report any bugs or feature requests to the GitHub issue tracker for
this project:

C<< <https://github.com/spicyjack/App-WADTools/issues> >>.

=head1 SUPPORT

You can find documentation for this script with the perldoc command.

    perldoc wadindex.pl

=head1 COPYRIGHT & LICENSE

Copyright (c) 2013 Brian Manning, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

# fin!
# vim: set shiftwidth=4 tabstop=4
