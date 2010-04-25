# Bot insulter object
package Insulter;

use strict;
use IDB;
use Net::OSCAR;
use Carp qw (croak confess);

our $idb        = IDB->new();
our %singletons = ();

our $MAX_BUDDIES = 0;
our $GROUP       = 'pimpz';
our $INSULT_MSG  = 'you\'re ugly';

our $LAST_SN     = '';

# this calls process on all instances
sub process {
    my $class = shift;

    foreach my $i (values %singletons) {
        $i->_process;
    }
}

# this calls do_one_loop on all instances
sub do_one_loop {
    my $class = shift;

    foreach my $i (values %singletons) {
        next unless $i && $i->o;
        $i->o->do_one_loop;
    }
}

# generate insulting message
sub insult_msg {
    return $INSULT_MSG;
}

# how many insulters are instantiated?
sub insulter_count {
    return scalar keys %singletons;
}

*new = \&instance;
sub instance {
    my ($class, %opts) = @_;

    my $debug = delete $opts{debug} || 0;

    my $sn = delete $opts{screenname} or croak "No screenname";

    return $singletons{$sn} if $singletons{$sn};

    my $pass            = delete $opts{password} or croak "No password";
    my $signon_callback = delete $opts{on_signon};
    my $die_callback = delete $opts{on_die};

    croak "Unknown options: " . join(', ', keys %opts) if scalar keys %opts;

    my $o = Net::OSCAR->new() or die "Could not create Net::OSCAR object";

    # set up callbacks
    $o->set_callback_im_in(\&o_im_in);
    $o->set_callback_buddy_info(\&o_buddy_info);
    $o->set_callback_buddylist_error(\&o_buddylist_error);
    $o->set_callback_admin_error(\&o_admin_error);
    $o->set_callback_error(\&o_error);
    $o->set_callback_signon_done(\&o_signed_on);
    $o->set_callback_buddylist_ok(\&o_buddylist_ok);

    my $aim_opts = {
        screenname     => $sn,
        password       => $pass,
#        pass_is_hashed => 1,
    };

    my $self = {
        o               => $o,
        opts            => $aim_opts,
        debug           => $debug,
        online          => 0,
        signon_callback => $signon_callback,
        buddy_list_ok   => 1,
        on_die          => $die_callback,
    };

    $self->{o}->{i} = $self;

    bless $self, $class;
    $singletons{$sn} = $self;

    return $self;
}

##### ACCESSORS
sub sn {
    my $self = shift;
    return $self->normalize($self->{opts}->{screenname});
}
sub o            { $_[0]->{o} }
sub online       { $_[0]->{online} }

##### METHODS

# adds a screen name to queue for insulting
# should probably never be called, mostly just for testing
sub insult {
    my ($self, $sn) = @_;

    $sn = $self->normalize($sn);

    return if grep { $_ eq $sn } $idb->queue;

    $idb->add_to_queue($sn);
}

##### SUPPORT METHODS

# processes next screen name in queue
sub _process {
    my $self = shift;

    my $sn = $idb->next_in_queue;

    # add the previous processed screen name to the queue
    # they won't be re-added if they were insulted
    $idb->add_to_queue($LAST_SN) if $LAST_SN;

    if ($sn) {
#        $self->dbg("Getting info on '$sn'");
        $self->get_info($sn);
        $LAST_SN = $sn;

        $self->pause(5);
    }

    $self->o->do_one_loop;

    return;
}

# a screen name has been determined to be online. deal with it
sub handle_sn_online {
    my ($self, $sn) = @_;

    $sn = $self->normalize($sn);

    return if $idb->insulted($sn);

    $self->send_insult($sn);
}

# send IM insulting this person
sub send_insult {
    my ($self, $sn) = @_;
    my $o = $self->o;

    my $msg = $self->insult_msg;

    $self->log_im(sn => $sn, to => 1, message => $msg);
    $o->send_im($sn, $msg);
    $idb->insulted($sn, 1);

    $self->pause(3);
}

# log IM in the DB
sub log_im {
    my ($self, %opts) = @_;

    $opts{other_sn} = $self->sn;

    $self->dbg("IM " . ($opts{to} ? 'to' : 'from') . " $opts{sn}: $opts{message}");

    $idb->log_im(%opts);
}

# safely adds a buddy to our buddy list
sub add_buddy {
    my ($self, $sn) = @_;

    # add to queue?

    $self->o->add_group($GROUP);
    $self->o->add_buddy($GROUP, $sn);
    $self->dbg("Adding buddy $sn");
    $self->save_buddy_list;
}

# waits and keeps processing
sub pause {
    my ($self, $secs) = @_;

    my $time = time();
    __PACKAGE__>do_one_loop while ($time + $secs > time());
}

# safely saves buddy list
sub save_buddy_list {
    my $self = shift;
    my $o = $self->o;

    # if we're waiting for a pending buddy list change, we should
    # pause for a few seconds to save again
    for (1..3) {
        $self->pause($_) unless $self->{buddy_list_ok};
    }
    unless ($self->{buddy_list_ok}) {
        $self->dbg("Waiting for buddy list to be safe timed out");
        return;
    }

    $self->{buddy_list_ok} = 0;
    $self->dbg("Committing buddy list");
    $o->commit_buddylist;
}

# call to destroy this object and remove it from the event processing
sub destroy {
    my $self = shift;
    delete $self->{o}->{i};
    delete $singletons{$self->sn};
}

sub dbg {
    my ($self, $msg) = @_;

    confess "Invalid self" unless ref $self;

    return unless $self->{debug};
    print STDERR $self->sn . ": $msg\n";
}

# remove spaces, make lowercase
sub normalize {
    my ($self, $str) = @_;
    $str =~ s/\s//g;
    return lc $str;
}

sub signon {
    my $self = shift;

#    print "sn: $self->{opts}->{screenname}\n";
#    print "pass: $self->{opts}->{password}\n";
#    print "hashed: $self->{opts}->{pass_is_hashed}\n";

    $self->o->signon(%{$self->{opts}});
    $self->dbg("Signing on to AIM");
}

sub get_info {
    my ($self, $sn) = @_;
    return $self->dbg("Not online") unless $self->online;
    $self->o->get_info($sn);
}

##### CALLBACKS

# callback: signed on to AIM
sub o_signed_on {
    my $o = shift;
    my $i = $o->i;
    $i->{online} = 1;

    $i->{signon_callback}->($i) if $i->{signon_callback};

    $i->dbg("Signed on to AIM");
}

# callback: our buddy list was saved ok.
# we can't do anything with our buddy list
# until AIM gives us the ok
sub o_buddylist_ok {
    my $o = shift;
    my $i = $o->i;
    $i->{buddy_list_ok} = 1;

    $i->dbg("Got buddy list ok");
}

# callback: error saving buddy list
sub o_buddylist_error {
    my ($o, $err, $what) = @_;
    my $i = $o->i;
    $i->{buddy_list_ok} = 1;

    $i->dbg("Error $err saving buddy list: $what");
}

# callback: got buddy info
sub o_buddy_info {
    my ($o, $sn, $data) = @_;
    my $i = $o->i;

    my $info;

    map { $info->{$_} = $data->{$_} } qw (mobile trial pay onsince free
                                          evil session_length admin flags
                                          aol extended_status away profile);

    $idb->save_sn_info(__PACKAGE__->normalize($sn), $info);

#    $i->dbg("Got info for $sn.");
    $i->handle_sn_online($sn);
}

# callback: AIM server error
sub o_admin_error {
    my ($o, $reqtype, $error) = @_;
    my $i = $o->i;

    $i->dbg("Admin error! Reqtype: $reqtype\nError: $error");
}

# callback: AIM error
sub o_error {
    my ($o, $conn, $error, $desc, $fatal) = @_;

    my $fatalwarn = $fatal ? "FATAL ERROR" : "Error";
    my $i = $o->i;

    if ($fatal) {
        $i->{on_die}->() if $i->{on_die};

        # remove this screen name from processing
        my $sn = $i->sn;
        delete $singletons{$sn};
    }

    # don't care about errors on getting info on logged-out users
    return if $error == 4;

    $i->dbg("$fatalwarn: $error ($desc)");
}

# callback: someone IMs bot
sub o_im_in {
    my ($o, $sender, $message, $is_away) = @_;
    my $i = $o->i;
    $sender = $i->normalize($sender);

    # strip html
    $message =~ s/<[^>]+>//g;

    $i->log_im(sn => $sender, message => $message, away => $is_away, to => 0);
}


# shady mixin
package Net::OSCAR;
sub i {
    my $self = shift;
    return $self->{i};
}

1;
