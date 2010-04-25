# IDB: Insult Database
# Provides various database functions for Insulter

package IDB;

use strict;
use Carp qw (croak);
use DBI;

$IDB::base       = '/srv/bot/insult';
$IDB::schemafile = $IDB::base . '/insult.sql';
$IDB::knownfile  = $IDB::base . '/known.txt';

sub load_sql {
    open my $fh, $IDB::schemafile or die "Can't open $IDB::schemafile: $!";
    my $sql = do { local $/; <$fh> };
    close $fh;
    split /;\s*/, $sql;
}

sub load_known {
    my ($self, $file) = @_;

    my $kfile = $file || $IDB::knownfile;
    open my $fh, $kfile or die "Can't open $kfile: $!";

    my @names;
    my @sn;
    my @bind;

    while (my $name = <$fh>) {
        $name =~ s/\s//g;
        push @names, $name;
        push @sn, 'sn';
        push @bind, '?';
    }

    if (scalar @names) {
        my $sth = $self->dbh->prepare("INSERT IGNORE INTO known (sn) VALUES (?)");
        $self->checkerr;

        $self->dbh->begin_work or die $self->dbh->errstr;

        if ($sth) {
            foreach my $name (@names) {
                $sth->execute($name);
            }
        }

        $self->dbh->commit;

        $self->checkerr;
    }

    close $fh;
}

# create db
sub initialize {
    my $self = shift;

    die "Schema file $IDB::schemafile missing!" unless -e $IDB::schemafile;

    my @sql = $self->load_sql;
    $self->dbh->do($_) for @sql;
}

sub new {
    my ($class, $insulter) = @_;

    my $self = {
        i   => $insulter,
    };

    bless $self, $class;

    my $dsn = "mysql:host=localhost;dbname=insulter";

    my $dbh = DBI->connect("dbi:mysql:$dsn","insulter","osama", { RaiseError => 0 })
        or die "Could not connect to DB: ";
    $self->{dbh} = $dbh;

    $self->initialize;

    return $self;
}

sub i   { $_[0]->{i} }
sub dbh { $_[0]->{dbh} }

# save some info on a screen name
sub save_sn_info {
    my ($self, $sn, $info) = @_;

    my $sql = "REPLACE INTO sn_info (sn, updated, prop, value) VALUES (?, ?, ?, ?)";

    my $sth = $self->dbh->prepare($sql);
    if (!$sth || $self->dbh->errstr) {
        $self->checkerr;
        return;
    }

    while (my ($k, $v) = each %$info) {
        $sth->execute($sn, time(), $k, $v);
        $self->checkerr;
    }

    $self->add_known($sn);
}

# getter/setter
# returns when insulted
sub insulted {
    my ($self, $sn, $insulted) = @_;

    my $sql = "SELECT when_insulted FROM sn WHERE insulted=1 AND sn=?";
    my $res = $self->dbh->selectrow_arrayref($sql, undef, $sn);
    my $when = $res ? $res->[0] : 0;

    unless (defined $insulted) {
        return $when;
    }

    $insulted = $insulted ? 1 : 0;

    my $sql = "REPLACE INTO sn (sn, insulted, when_insulted) VALUES (?, ?, ?)";
    $self->dbh->do($sql, undef, $sn, $insulted, time());

    $self->add_known($sn);

    $self->checkerr;
    return time();
}

# logs this IM in the DB
sub log_im {
    my ($self, %params) = @_;

    my $sn       = delete $params{sn}       or croak "No screenname";
    my $message  = delete $params{message} || '[Empty message]';
    my $other_sn = delete $params{other_sn} or croak "No other";
    my $away     = delete $params{away} ? 1 : 0;

    my $to       = delete $params{to};
    $to = $to ? 1 : 0;

    croak "Invalid params passed to log_im" if (scalar keys %params);

    my $sql = "INSERT INTO im_log (sn, im_to, im_when, other_sn, message, away) VALUES (?, ?, ?, ?, ?, ?)";
    $self->dbh->do($sql, undef, $sn, $to, time(), $other_sn, $message, $away);
    $self->checkerr;

    $self->add_known($sn);
}

# adds a SN to insult queue
sub add_to_queue {
    my ($self, $sn, $pos, $force) = @_;

    $pos ||= $self->max_queue_pos + 1;

    if ($force) {
        # delete from queue and known
        $self->dbh->do("DELETE FROM queue WHERE sn=?", undef, $sn);
        $self->checkerr;
        $self->dbh->do("DELETE FROM sn WHERE sn=?", undef, $sn);
        $self->checkerr;
    } else {
        # don't add if already insulted
        return if $self->insulted($sn) && !$force;
    }

    $self->dbh->do("INSERT IGNORE INTO queue (sn, added, pos) VALUES (?, ?, ?)", undef, $sn, time(), $pos);
    $self->checkerr;
}

# adds to front of queue
sub add_to_front_of_queue {
    my ($self, $sn, $force) = @_;

    my $min_pos = $self->min_queue_pos - 1;
    $self->add_to_queue($sn, $min_pos, $force);
}

# gets entire queue
# returns: list of screen names in queue
sub queue {
    my $self = shift;

    my $res = $self->dbh->selectrow_arrayref("SELECT sn FROM queue");
    $self->checkerr;

    return $res ? @$res : undef;
}

# gets next SN to insult out of the queue
sub next_in_queue {
    my $self = shift;

    my $sn;
    my $res;

    $res = $self->dbh->selectrow_arrayref("SELECT MIN(pos) FROM queue");
    $self->checkerr;

    if ($res && defined $res->[0]) {
        $sn = $self->dbh->selectrow_arrayref("SELECT sn FROM queue WHERE pos = ?", undef, $res->[0]);
        $self->checkerr;

        # remove from queue
        $self->dbh->do("DELETE FROM queue WHERE pos = ?", undef, $res->[0]);
        $self->checkerr;
    }

    return $sn ? $sn->[0] : undef;
}

sub max_queue_pos {
    my $self = shift;

    my $maxres = $self->dbh->selectrow_arrayref("SELECT MAX(pos) FROM queue");
    $self->checkerr;

    my $max = $maxres ? $maxres->[0] : 1;
    $max ||= 0; # set to 0 if undef

    return $max;
}

sub min_queue_pos {
    my $self = shift;

    my $maxres = $self->dbh->selectrow_arrayref("SELECT MIN(pos) FROM queue");
    $self->checkerr;

    my $max = $maxres ? $maxres->[0] : 1;
    $max ||= 0; # set to 0 if undef

    return $max;
}

# mark this SN as known to be valid
sub add_known {
    my ($self, $sn) = @_;

    return unless $sn;
    $sn =~ s/\s//g;
    $sn = lc $sn;

    my $sql = "INSERT IGNORE INTO known (sn) VALUES (?)";
    $self->dbh->do($sql, undef, $sn);
    $self->checkerr;
}

sub get_known {
    my $self = shift;

    my $res = $self->dbh->selectall_arrayref("SELECT sn FROM known ORDER BY sn");
    $self->checkerr;

    return $res ? map { $_->[0] } @$res : 0;
}

sub checkerr {
    my $self = shift;
    print $self->dbh->errstr if $self->dbh->errstr;
}

1;
