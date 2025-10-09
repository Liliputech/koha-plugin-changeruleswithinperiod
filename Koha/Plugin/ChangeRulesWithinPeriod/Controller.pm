package Koha::Plugin::ChangeRulesWithinPeriod::Controller;

use Modern::Perl;
use Koha::Plugin::ChangeRulesWithinPeriod;
use Mojo::Base 'Mojolicious::Controller';

our $plugin = Koha::Plugin::ChangeRulesWithinPeriod->new();

sub config {
    my $c = shift->openapi->valid_input or return;
    return $c->render(
	status => 200,
	openapi => {
	    start_date     => $plugin->retrieve_data('start_date'),
            end_date       => $plugin->retrieve_data('end_date'),
            rule_name      => $plugin->retrieve_data('rule_name'),
            rule_new_value => $plugin->retrieve_data('rule_new_value'),
	    ignore_zero    => $plugin->retrieve_data('ignore_zero'),
	    library        => $plugin->retrieve_data('library'),
	}
        );
}
