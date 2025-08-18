package Koha::Plugin::ChangeRulesWithinPeriod;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
use C4::Context;

use Koha::DateUtils qw( dt_from_string );

## Here we set our plugin version
our $VERSION = "1";
our $MINIMUM_VERSION = "24.11";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Change Rules Within Period',
    author          => 'Arthur Suzuki',
    date_authored   => '2025-08-11',
    date_updated    => "2025-08-11",
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'This plugin helps you define a date range '
	. 'within which a rule can be set to a new value. '
	. 'After the end date the rule is set back to its old value. '
	. 'Warning : All circulation rules will be affected by the change.',
    namespace       => 'changeruleswithinperiod',
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('saved_rules_values');
    warn "Install ChangeRulesWithinPeriod";
    return C4::Context->dbh->do( "
        CREATE TABLE IF NOT EXISTS $table (
            `id` INT( 11 ) NOT NULL PRIMARY KEY,
            `rule_value` VARCHAR(32),
	    UNIQUE (`id`)
        ) ENGINE = INNODB;
    " );
}

sub backup_circulation_rules {
    my ( $self ) = @_;
    my $rule_name=$self->retrieve_data('rule_name');
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("SELECT id, rule_value FROM circulation_rules WHERE rule_name = ?");
    $sth->execute($rule_name);
    my @previous_rules;
    while ( my $data = $sth->fetchrow_hashref() ) {
        push( @previous_rules, $data );
    }
    my $saved_values = $self->get_qualified_table_name('saved_rules_values');
    foreach my $rule (@previous_rules) {
	my $query = "INSERT INTO $saved_values (id, rule_value) VALUES ( ? , ? )";
        $sth = $dbh->prepare($query);
        $sth->execute($rule->{'id'}, $rule->{'rule_value'});
    }
}

sub set_new_rule_value {
    my ( $self ) = @_;
    my $rule_name=$self->retrieve_data('rule_name');
    my $rule_value=$self->retrieve_data('rule_new_value');
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("UPDATE circulation_rules SET rule_value=? WHERE rule_name = ?");
    $sth->execute( $rule_value, $rule_name );
}

sub restore_circulation_rules {
    my ( $self ) = @_;
    my $dbh = C4::Context->dbh;
    my $saved_values = $self->get_qualified_table_name('saved_rules_values');
    my $sth = $dbh->prepare("SELECT * FROM $saved_values");
    $sth->execute();
    my @previous_rules;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @previous_rules, $data );
    }
    foreach my $rule (@previous_rules) {
        $sth = $dbh->prepare("UPDATE circulation_rules SET rule_value=? WHERE id=?");
        $sth->execute($rule->{'rule_value'}, $rule->{'id'});
	$sth = $dbh->prepare("DELETE FROM $saved_values WHERE id=?");
	$sth->execute($rule->{'id'});
    }
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            start_date     => $self->retrieve_data('start_date'),
            end_date       => $self->retrieve_data('end_date'),
            rule_name      => $self->retrieve_data('rule_name'),
            rule_new_value => $self->retrieve_data('rule_new_value'),
        );

        $self->output_html( $template->output() );
    }
    else {
        $self->store_data(
            {
                start_date     => $cgi->param('start_date'),
                end_date       => $cgi->param('end_date'),
                rule_name      => $cgi->param('rule_name'),
                rule_new_value => $cgi->param('rule_new_value'),
            }
        );
	print $self->{'cgi'}->redirect("/cgi-bin/koha/admin/smart-rules.pl");
	return;
    }
}

=head3 cronjob_nightly

Plugin hook running code from a cron job

=cut

sub cronjob_nightly {
    my ( $self ) = @_;
    my $today = DateTime->now->truncate(to => 'day');
    my $start_date = dt_from_string($self->retrieve_data('start_date'), 'iso');
    my $end_date = dt_from_string($self->retrieve_data('end_date'), 'iso');

    if ( $today < $start_date ) {
        print "nothing to do : before start_date";
        return;
    }

    if ( $today == $start_date ) {
        print "backing up and setting rule to its new value";
        $self->backup_circulation_rules();
        $self->set_new_rule_value();
        return;
    }

    if ( $today == $end_date ) {
        print "restoring previous rules values";
        $self->restore_circulation_rules();
        return;
    }

    if ( $today > $end_date ) {
        print "nothing to do : after end_date";
        return;
    }

    print "nothing to do : within period";
    return;
}
