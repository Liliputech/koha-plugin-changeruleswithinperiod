package Koha::Plugin::ChangeRulesWithinPeriod::Controller;

use Modern::Perl;
use Koha::Plugin::ChangeRulesWithinPeriod;
use Mojo::Base 'Mojolicious::Controller';

our $plugin = Koha::Plugin::ChangeRulesWithinPeriod->new();

sub config {
    my $c = shift->openapi->valid_input or return;
    my $library_code = $c->param('library') || 'default';
    
    my $multi_config = $plugin->get_multi_config();
    my $config = $plugin->get_config_for_library($library_code);
    
    return $c->render(
	status => 200,
	openapi => {
	    library_code   => $library_code,
	    start_date     => $config->{start_date},
        end_date       => $config->{end_date},
        rule_name      => $config->{rule_name},
        rule_new_value => $config->{rule_new_value},
	    ignore_zero    => $config->{ignore_zero},
	    alert_warning  => $config->{alert_warning},
	    alert_danger   => $config->{alert_danger},
	    configure_link => $config->{configure_link},
	    multi_config   => $multi_config,
	    configured_libraries => [$plugin->get_configured_libraries()],
	}
        );
}
