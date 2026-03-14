package Koha::Plugin::ChangeRulesWithinPeriod::Controller;

use Modern::Perl;
use Koha::Plugin::ChangeRulesWithinPeriod;
use Mojo::Base 'Mojolicious::Controller';

our $plugin = Koha::Plugin::ChangeRulesWithinPeriod->new();

sub config {
    my $c = shift->openapi->valid_input or return;
    my $multi_config = $plugin->get_multi_config();
    my $config = $multi_config->{default};
    return $c->render(
        status => 200,
        openapi => {
            alert_warning  => $config->{alert_warning},
            alert_danger   => $config->{alert_danger},
            configure_link => $config->{configure_link},
        });
}
