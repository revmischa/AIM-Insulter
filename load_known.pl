#!/usr/bin/perl
use strict;
use IDB;

my $idb = IDB->new();
$idb->load_known($ARGV[0]);
