package Koha::Plugin::ChangeRulesWithinPeriod;

## It's good practice to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);
use C4::Context;
use Mojo::JSON qw(decode_json);

use Koha::DateUtils qw( dt_from_string );
use Koha::Libraries;
use JSON qw( encode_json decode_json );

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

## Get all libraries for the library selector
sub get_libraries {
    my ( $self ) = @_;
    my @libraries;
    my $libraries_rs = Koha::Libraries->search({}, { order_by => 'branchname' });
    while ( my $library = $libraries_rs->next ) {
        push @libraries, {
            branchcode => $library->branchcode,
            branchname => $library->branchname,
        };
    }
    return @libraries;
}

## Get multi-configuration data structure
sub get_multi_config {
    my ( $self ) = @_;
    my $config_json = $self->retrieve_data('multi_config');
    
    if ($config_json) {
        return decode_json($config_json);
    }
    
    # If no multi-config exists, migrate from old single config
    return $self->migrate_to_multi_config();
}

## Migrate existing single configuration to multi-config structure
sub migrate_to_multi_config {
    my ( $self ) = @_;
    
    my $config = {
        default => {
            start_date     => $self->retrieve_data('start_date') || '',
            end_date       => $self->retrieve_data('end_date') || '',
            rule_name      => $self->retrieve_data('rule_name') || 'issuelength',
            rule_new_value => $self->retrieve_data('rule_new_value') || '',
            ignore_zero    => $self->retrieve_data('ignore_zero') || '0',
        },
        library_configs => {}
    };
    
    # If there was a specific library set in old config, move it to library_configs
    my $old_library = $self->retrieve_data('library');
    if ($old_library && $old_library ne '') {
        $config->{library_configs}->{$old_library} = {
            start_date     => $self->retrieve_data('start_date') || '',
            end_date       => $self->retrieve_data('end_date') || '',
            rule_name      => $self->retrieve_data('rule_name') || 'issuelength',
            rule_new_value => $self->retrieve_data('rule_new_value') || '',
            ignore_zero    => $self->retrieve_data('ignore_zero') || '0',
        };
        # Clear default config since it was library-specific
        $config->{default} = {
            start_date     => '',
            end_date       => '',
            rule_name      => 'issuelength',
            rule_new_value => '',
            ignore_zero    => '0',
        };
    }
    
    $self->store_data({ multi_config => encode_json($config) });
    return $config;
}

## Store multi-configuration
sub store_multi_config {
    my ( $self, $config ) = @_;
    $self->store_data({ multi_config => encode_json($config) });
}

## Get configuration for a specific library (falls back to default)
sub get_config_for_library {
    my ( $self, $library_code ) = @_;
    my $multi_config = $self->get_multi_config();
    
    # Return library-specific config if it exists
    if ($library_code && exists $multi_config->{library_configs}->{$library_code}) {
        return $multi_config->{library_configs}->{$library_code};
    }
    
    # Fall back to default config
    return $multi_config->{default};
}

## Get all configured libraries (libraries that have specific configurations)
sub get_configured_libraries {
    my ( $self ) = @_;
    my $multi_config = $self->get_multi_config();
    return keys %{$multi_config->{library_configs}};
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
    my ( $self, $library_code ) = @_;
    my $config = $self->get_config_for_library($library_code);
    my $rule_name = $config->{rule_name};
    my $ignore_zero = $config->{ignore_zero};
    my $dbh = C4::Context->dbh;
    my $query = "SELECT id, rule_value FROM circulation_rules WHERE rule_name = ?";
    my @params = ($rule_name);
    
    if ($ignore_zero) {
	$query .= " AND rule_value != 0";
    }
    
    if ($library_code && $library_code ne '') {
        $query .= " AND branchcode = ?";
        push @params, $library_code;
    }
    
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
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
    my ( $self, $library_code ) = @_;
    my $config = $self->get_config_for_library($library_code);
    my $rule_name = $config->{rule_name};
    my $rule_value = $config->{rule_new_value};
    my $ignore_zero = $config->{ignore_zero};
    my $dbh = C4::Context->dbh;
    my $query = "UPDATE circulation_rules SET rule_value=? WHERE rule_name = ?";
    my @params = ($rule_value, $rule_name);
    
    if ($ignore_zero) {
	$query .= " AND rule_value != 0";
    }
    
    if ($library_code && $library_code ne '') {
        $query .= " AND branchcode = ?";
        push @params, $library_code;
    }
    
    my $sth = $dbh->prepare($query);
    $sth->execute(@params);
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
    my ( $self, $library_code ) = @_;
    my $config = $self->get_config_for_library($library_code);
    
    # Skip if no dates configured
    return 0 unless ($config->{start_date} && $config->{end_date});
    
    my $today = DateTime->now->truncate(to => 'day')->ymd('');
    my $start_date = dt_from_string($config->{start_date}, 'iso')->ymd('');
    my $end_date = dt_from_string($config->{end_date}, 'iso')->ymd('');
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

    # Get current editing context (which library config we're editing)
    my $editing_library = $cgi->param('editing_library') || 'default';
    my $multi_config = $self->get_multi_config();

    if ( $cgi->param('save') ) {
        # Save configuration for the currently selected library
        my $config_data = {
            start_date     => $cgi->param('start_date'),
            end_date       => $cgi->param('end_date'),
            rule_name      => $rule_name,
            rule_new_value => $cgi->param('rule_new_value'),
            ignore_zero    => $cgi->param('ignore_zero'),
        };

        if ($editing_library eq 'default') {
            $multi_config->{default} = $config_data;
        } else {
            $multi_config->{library_configs}->{$editing_library} = $config_data;
        }

        $self->store_multi_config($multi_config);
    }

    # Handle library configuration deletion
    if ( $cgi->param('delete_config') ) {
        my $library_to_delete = $cgi->param('delete_config');
        if ($library_to_delete ne 'default' && exists $multi_config->{library_configs}->{$library_to_delete}) {
            delete $multi_config->{library_configs}->{$library_to_delete};
            $self->store_multi_config($multi_config);
            # Reset editing context to default after deletion
            $editing_library = 'default';
        }
    }

    # Get current configuration for the editing context
    my $current_config;
    if ($editing_library eq 'default') {
        $current_config = $multi_config->{default};
    } else {
        $current_config = $multi_config->{library_configs}->{$editing_library} || {
            start_date     => '',
            end_date       => '',
            rule_name      => 'issuelength',
            rule_new_value => '',
            ignore_zero    => '0',
        };
    }

    my $template = $self->get_template({ file => 'configure.tt' });
    my @saved_rules = $self->get_saved_rules();
    my @libraries = $self->get_libraries();
    my @configured_libraries = $self->get_configured_libraries();
    my $save = $cgi->param('save');

    ## Pass current configuration and multi-config context to template
    $template->param(
	start_date          => $current_config->{start_date},
	end_date            => $current_config->{end_date},
	rule_name           => $current_config->{rule_name},
	rule_new_value      => $current_config->{rule_new_value},
	ignore_zero         => $current_config->{ignore_zero},
	editing_library     => $editing_library,
	within_period       => $self->retrieve_data('active'),
	saved_rules         => \@saved_rules,
	libraries           => \@libraries,
	configured_libraries => \@configured_libraries,
	saved_config        => $save,
    );
    $self->output_html( $template->output() );
    return;
}

=head3 cronjob_nightly

Plugin hook running code from a cron job

=cut

sub cronjob_nightly {
    my ( $self ) = @_;
    my $multi_config = $self->get_multi_config();
    my $active_configs = $self->retrieve_data('active_configs') || '{}';
    $active_configs = decode_json($active_configs);

    # Check default configuration
    $self->process_library_config('default', $active_configs);

    # Check each library-specific configuration
    foreach my $library_code (keys %{$multi_config->{library_configs}}) {
        $self->process_library_config($library_code, $active_configs);
    }

    # Store updated active configs
    $self->store_data({ active_configs => encode_json($active_configs) });
}

sub process_library_config {
    my ( $self, $library_code, $active_configs ) = @_;
    my $is_active = $active_configs->{$library_code} || 0;
    my $is_within_period = $self->is_within_period($library_code);

    if ( $is_within_period and !$is_active ) {
        print "backing up rules values for library: $library_code\n";
        $self->backup_circulation_rules($library_code);
        $self->set_new_rule_value($library_code);
        $active_configs->{$library_code} = 1;
        return;
    }

    if ( !$is_within_period and $is_active ) {
        print "restoring previous rules values for library: $library_code\n";
        $self->restore_circulation_rules();
        $active_configs->{$library_code} = 0;
        return;
    }

    if ( $is_within_period ) {
        print "within period but nothing to do for library: $library_code\n";
        return;
    }

    print "out of period : nothing to do for library: $library_code\n";
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
