#!/usr/bin/perl -w

###############################################################################
# taskopen - file based notes with taskwarrior
#
# Copyright 2010-2013, Johannes Schlatow.
# All rights reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the
#
#     Free Software Foundation, Inc.,
#     51 Franklin Street, Fifth Floor,
#     Boston, MA
#     02110-1301
#     USA
#
###############################################################################

use JSON qw( decode_json );     # From CPAN
use strict;
use warnings;

my $HOME = $ENV{"HOME"};
my $XDG = "xdg-open";

if ($^O =~ m/.*darwin.*/) { #OSX
   $XDG = "open";
}

my $cfgfile = "$HOME/.taskopenrc";
my %config;
open(CONFIG, "$cfgfile") or die "can't open $cfgfile: $!";
while (<CONFIG>) {
    chomp;
    s/#.*//; # Remove comments
    s/^\s+//; # Remove opening whitespace
    s/\s+$//;  # Remove closing whitespace
    next unless length;
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    $value =~ s/"(.*)"/$1/;
    $value =~ s/'(.*)'/$1/;
    $config{$key} = $value;
}

my $TASKBIN;
if (exists $config{"TASKBIN"}) {
    $TASKBIN = $config{"TASKBIN"};
}
else {
    $TASKBIN = '/usr/bin/task';
}

my $FOLDER;
if (exists $config{"FOLDER"}) {
    $FOLDER = $config{"FOLDER"};
}
else {
    $FOLDER = "~/tasknotes/";
}

my $EXT;
if (exists $config{"EXT"}) {
    $EXT = $config{"EXT"};
}
else {
    $EXT = ".txt";
}

my $NOTEMSG;
if (exists $config{"NOTEMSG"}) {
    $NOTEMSG = $config{"NOTEMSG"};
}
else {
    $NOTEMSG = "Notes";
}

my $BROWSER;
if (exists $config{"BROWSER"}) {
    $BROWSER = $config{"BROWSER"};
}
else {
    $BROWSER = $XDG;
}

my $EDITOR;
if (exists $config{"EDITOR"}) {
    $EDITOR = $config{"EDITOR"};
}
else {
    $EDITOR = "vim";
}

my $NOTES_FILE;
if (exists $config{"NOTES_FILE"}) {
    $NOTES_FILE = $config{"NOTES_FILE"};
}
else {
    $NOTES_FILE = "${FOLDER}UUID$EXT";
}

my $NOTES_CMD;
if (exists $config{"NOTES_CMD"}) {
    $NOTES_CMD = $config{"NOTES_CMD"};
}
else {
    $NOTES_CMD = "$EDITOR $NOTES_FILE";
}

my $EXCLUDE;
if (exists $config{"EXCLUDE"}) {
    $EXCLUDE = $config{"EXCLUDE"};
}
else {
    $EXCLUDE = "status.is:pending";
}

my $DEBUG;
if (exists $config{"DEBUG"} && $config{"DEBUG"} =~ m/\d+/) {
    $DEBUG = $config{"DEBUG"};
}
else {
    $DEBUG = 0;
}

my $FILEREGEX = qr{^(?:(\S*):\s)?((?:\/|www|http|\.|~|Message-[Ii][Dd]:|message:|$NOTEMSG).*)};

sub create_cmd {
    my $ann = $_[0];
    my $FORCE = $_[1];
    my $file = $ann->{"file"};

    if ($FORCE) {
        if ($file eq $NOTEMSG) {
            $file = $NOTES_FILE;
            $file =~ s/UUID/$ann->{"uuid"}/g;
        }

        $file =~ s/^~/$HOME/;
        return qq{$FORCE "$file"};
    }

    my $cmd;
    if ($file eq $NOTEMSG) {
        $cmd = $NOTES_CMD;
        $cmd =~ s/UUID/$ann->{"uuid"}/g;
        $cmd = qq/$ENV{"SHELL"} -c "$cmd"/;
    }
    elsif ($file =~ m/^www.*/ ) {
        # prepend http://
        $cmd = qq{$BROWSER "http://$file"};
    }
    elsif ($file =~ m/^http.*/ ) {
        $cmd = qq{$BROWSER "$file"};
    }
    elsif ($file =~ m/Message-[Ii][Dd]/ ) {
        $cmd = qq{echo "$file" | muttjump && clear};
    }
    else {
        $file =~ s/^~/$HOME/;
        my $filetype = qx{file "$file"};
        if ($filetype =~ m/text/ ) {
            $cmd = qq/$ENV{'SHELL'} -c "$EDITOR '$file'"/;
        }
        else {
            # use XDG for unknown file types
            $cmd = qq{$XDG "$file"};
        }
    }

    return $cmd;
}

# argument parsing
my $FILTER = "";
my $ID_CMD = "ids";
my $LABEL;
my $HELP;
my $LIST;
my $FORCE;
for (my $i = 0; $i <= $#ARGV; ++$i) {
    my $arg = $ARGV[$i];
    if ($arg eq "-h") {
        $HELP = 1;
    }
    elsif ($arg eq "-l") {
        $LIST = 1;
    }
    elsif ($arg eq "-n") {
        $FILEREGEX = qr{^(?:(\S*):\s)?((?:$NOTEMSG).*)};
    }
    elsif ($arg eq "-a") {
        $EXCLUDE = "";
    }
    elsif ($arg eq "-aa") {
        $EXCLUDE = "";
        $ID_CMD  = "uuids";
    }
    elsif ($arg eq "-e") {
        if ($FORCE) {
            print "Cannot use -e in conjunction with -x";
            exit 1;
        }
        $FORCE = $EDITOR;
    }
    elsif ($arg eq "-x") {
        if ($FORCE) {
            print "Cannot use -x in conjunction with -e";
            exit 1;
        }
        $FORCE = $ARGV[++$i];
    }
    elsif ($arg =~ m/\\+(.+)/) {
        $LABEL = $1;
    }
    else {
        $FILTER = "$FILTER $arg";
    }
}

if ($HELP) {
	print "Usage: $0 [-h] [-l] [id|filter1 filter2 ... filterN] [\\\\label]\n\n";

    print "-h          Show this text\n";
    print "-l          List-only mode, does not open any file\n";
    print "-n          Only show/open notes file, i.e. annotations containing '$NOTEMSG'\n";
    print "-a          Query all active tasks; clears the EXCLUDE filter\n";
    print "-aa         Query all tasks, i.e. completed and deleted tasks as well (very slow)\n";
    print "-e          Force to open file with EDITOR\n";
    print "-x ['cmd']  Execute file, optionally prepend cmd to the command line\n";

    print "\nCurrent configuration:\n";
    print "BROWSER    = $BROWSER\n";
    print "TASKBIN    = $TASKBIN\n";
    print "FOLDER     = $FOLDER\n";
    print "EXT        = $EXT\n";
    print "EDITOR     = $EDITOR\n";
    print "NOTEMSG    = $NOTEMSG\n";
    print "NOTES_FILE = $NOTES_FILE\n";
    print "NOTES_CMD  = $NOTES_CMD\n";
    print "EXCLUDE    = $EXCLUDE\n";
    print "DEBUG      = $DEBUG\n";

	exit 1;
}


if ($DEBUG > 0) {
    printf("[DEBUG] Applying filter: $EXCLUDE$FILTER\n");
}
my $ID = qx{$TASKBIN $ID_CMD $EXCLUDE$FILTER};
chop($ID);

# query IDs and parse json
my $json = qx{$TASKBIN $ID _query};
my @decoded_json = @{decode_json("[$json]")};

# Reorganize data
my @annotations;
foreach my $task (@decoded_json) {
    if (exists $task->{"annotations"}) {
        foreach my $ann (@{$task->{"annotations"}}) {
            if ($ann->{"description"} =~ m/$FILEREGEX/) {
                if (!$LABEL || ($1 && $LABEL eq $1) ) {
                    my %entry = ( "ann"         => $2,
                                  "uuid"        => $task->{"uuid"},
                                  "file"        => $2,
                                  "label"       => $1,
                                  "description" => $task->{"description"});
                    push(@annotations, \%entry);
                }
                elsif ($DEBUG > 0) {
                    if (!$1) {
                        printf(qq/[DEBUG] Skipping unlabeled annotation "$ann->{"description"}"\n/);
                    }
                    else {
                        printf(qq/[DEBUG] Skipping label "$1"\n/);
                    }
                }
            }
            elsif ($DEBUG > 0) {
                printf(qq/[DEBUG] Skipping annotation "$ann->{"description"}"\n/);
            }
        }
    }
}

if ($#annotations < 0) {
    print "No annotation found.\n";
    exit 1;
}
else {
    my $num = $#annotations + 1;
    print "$num annotation(s) found\n";
}

# choose an annotation/file to open
my $choice = 0;
if ($#annotations > 0 || $LIST) {
    print "\n";
    print "Please select an annotation:\n";

    my $i = 1;
    foreach my $ann (@annotations) {
        my $text = qq/$ann->{'ann'} ("$ann->{'description'}")/;
        print "    $i) $text\n";
        if ($LIST) {
            my $cmd = create_cmd($ann, $FORCE);
            print "       executes: $cmd\n";
        }
        $i++;
    }

    if ($LIST) {
        exit 0;
    }

    # read input
    print "Type number: ";
    $choice = <STDIN>;
    chomp ($choice);

    # check input
    if ($choice !~ m/\d+/) {
        print "$choice is not a number\n";
        exit 1;
    }
    elsif ($choice < 1 || $choice >= $i) {
        print "$choice is not a valid number\n";
        exit 1;
    }
}

##############################################
#open annotations[$choice] with an appropriate program

my $ann  = $annotations[$choice-1];
exec(create_cmd($ann, $FORCE));