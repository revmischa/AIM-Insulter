#!/usr/bin/perl
use strict;
use Insulter;
use Digest::MD5 qw(md5);
use Getopt::Long;

my $verbose = 0;
GetOptions("verbose" => \$verbose);

my @insulter_logins = (
    ['username', 'pw'], # ...
);

my @insulters;
my $online_count = 0;

foreach my $login (@insulter_logins) {
    my $i = Insulter->new(
                          debug      => $verbose,
                          screenname => $login->[0],
                          password   => $login->[1],
                          on_signon  => \&signed_on,
                          on_die     => sub { $online_count--; },
                          );
    push @insulters, $i;

    $i->signon;

    my $t = time();
    while ($t + 5 > time()) {
        Insulter->do_one_loop;
    }
}

while ($online_count < Insulter->insulter_count) {
    Insulter->do_one_loop;
}

print "All online\n" if $verbose;

Insulter->process while (1);

sub signed_on {
    my $i = shift;
    my $o = $i->o;

    $online_count++;
}
