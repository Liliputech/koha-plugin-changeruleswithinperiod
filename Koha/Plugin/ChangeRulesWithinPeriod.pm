package Koha::Plugin::ChangeRulesWithinPeriod;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
use C4::Context;
use Mojo::JSON qw(decode_json);

use Koha::DateUtils qw( dt_from_string );

## Here we set our plugin version
our $VERSION = "1.3";
our $MINIMUM_VERSION = "23.11";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'Change Rules Within Period',
    author          => 'Arthur Suzuki',
    date_authored   => '2025-08-11',
    date_updated    => '2025-10-03',
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
    my $ignore_zero = $self->retrieve_data('ignore_zero');
    my $dbh = C4::Context->dbh;
    my $query = "SELECT id, rule_value FROM circulation_rules WHERE rule_name = ?";
    if ($ignore_zero) {
	$query .= " AND rule_value != 0";
    }
    my $sth = $dbh->prepare($query);
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
    my $ignore_zero = $self->retrieve_data('ignore_zero');
    my $dbh = C4::Context->dbh;
    my $query = "UPDATE circulation_rules SET rule_value=? WHERE rule_name = ?";
    if ($ignore_zero) {
	$query .= " AND rule_value != 0";
    }
    my $sth = $dbh->prepare($query);
    $sth->execute( $rule_value, $rule_name );
}

sub get_saved_rules {
    my ( $self ) = @_;
    my $dbh = C4::Context->dbh;
    my $saved_values = $self->get_qualified_table_name('saved_rules_values');
    my $sth = $dbh->prepare("
       SELECT backup.*, branchcode, categorycode, itemtype, rule_name
       FROM $saved_values backup
       LEFT JOIN circulation_rules
       ON backup.id=circulation_rules.id
       ");
    $sth->execute();
    my @previous_rules;
    while ( my $data = $sth->fetchrow_hashref ) {
        push( @previous_rules, $data );
    }
    return @previous_rules;
}

sub restore_circulation_rules {
    my ( $self ) = @_;
    my $dbh = C4::Context->dbh;
    my $saved_values = $self->get_qualified_table_name('saved_rules_values');
    my @previous_rules = $self->get_saved_rules();
    my $sth;
    foreach my $rule (@previous_rules) {
        $sth = $dbh->prepare("UPDATE circulation_rules SET rule_value=? WHERE id=?");
        $sth->execute($rule->{'rule_value'}, $rule->{'id'});
	$sth = $dbh->prepare("DELETE FROM $saved_values WHERE id=?");
	$sth->execute($rule->{'id'});
    }
}

sub is_within_period {
    my ( $self ) = @_;
    my $today = DateTime->now->truncate(to => 'day')->ymd('');
    my $start_date = dt_from_string($self->retrieve_data('start_date'), 'iso')->ymd('');
    my $end_date = dt_from_string($self->retrieve_data('end_date'), 'iso')->ymd('');
    return 0 unless ( $end_date > $start_date);
    if ($today < $start_date) { return 0; }
    if ($today > $end_date) { return 0; }
    return 1;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $rule_name = "issuelength";

    if ( $cgi->param('rule_name') ) {
	$rule_name = $cgi->param('rule_name');
    }

    if ( $cgi->param('save') ) {
        $self->store_data(
            {
                start_date     => $cgi->param('start_date'),
                end_date       => $cgi->param('end_date'),
                rule_name      => $rule_name,
                rule_new_value => $cgi->param('rule_new_value'),
		ignore_zero    => $cgi->param('ignore_zero'),
            }
	);
    }

    my $template = $self->get_template({ file => 'configure.tt' });
    my @saved_rules = $self->get_saved_rules();
    ## Grab the values we already have for our settings, if any exist
    $template->param(
	start_date     => $self->retrieve_data('start_date'),
	end_date       => $self->retrieve_data('end_date'),
	rule_name      => $self->retrieve_data('rule_name'),
	rule_new_value => $self->retrieve_data('rule_new_value'),
	ignore_zero    => $self->retrieve_data('ignore_zero'),
	within_period  => $self->retrieve_data('active'),
	saved_rules    => \@saved_rules,
	saved_config   => $cgi->param('save')
    );
    $self->output_html( $template->output() );
    return;
}

=head3 cronjob_nightly

Plugin hook running code from a cron job

=cut

sub cronjob_nightly {
    my ( $self ) = @_;
    my $is_active = $self->retrieve_data('active');
    my $is_within_period = $self->is_within_period();

    if ( $is_within_period and !$is_active ) {
	print "backing up rules values";
        $self->backup_circulation_rules();
        $self->set_new_rule_value();
	$self->store_data( { active => 1 } );
        return;
    }

    if ( !$is_within_period and $is_active ) {
        print "restoring previous rules values";
	$self->restore_circulation_rules();
	$self->store_data( { active => 0 } );
        return;
    }

    if ( $is_within_period ) {
	print "within period but nothing to do";
	return;
    }

    print "out of period : nothing to do";
    return;
}

sub intranet_js {
    my ( $self ) = @_;
    return '<script>' . $self->mbf_read('checkdates.js') . '</script>';
}

sub static_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('staticapi.json');
    my $spec     = decode_json($spec_str);

    return $spec;
}

sub api_routes {
    my ( $self, $args ) = @_;
    my $spec_str;
    $spec_str = $self->mbf_read('openapi.json');
    my $spec = decode_json($spec_str);
    return $spec;
}

sub api_namespace {
    my ( $self ) = @_;
    return 'changerules';
}
1;
