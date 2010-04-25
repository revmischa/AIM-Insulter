#!/usr/bin/perl
use strict;
use lib '/srv/bot/insult';
use IDB;
use Getopt::Long;

my $front;
my $pos;
my $force;

GetOptions('position=i' => \$pos,
           'front|f'    => \$front,
           'force'      => \$force,);

my $sn = shift @ARGV;

usage() unless $sn;

$sn =~ s/\W//g and die usage();
$sn = lc $sn;

print "Invalid screen name: $sn\n" unless $sn && length($sn) <= 16;

my $idb = IDB->new();

if ($front) {
    $idb->add_to_front_of_queue($sn, $force);
} else {
    $idb->add_to_queue($sn, $pos, $force);
}

my $frontof = $front ? 'front of ' : '';

print "Added $sn to ${frontof}queue\n";

sub usage {
    print "Usage: queueadd.pl (screen name) [--position=n] [--front]\n";
    exit;
}


