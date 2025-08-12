#Change Rule Within Period

## Introduction

This plugin will help you define a date range within which the circulation rules will be altered.

For example, during the summer vacations, you want all loans to be extended to 60 days.

To do this you will need to define the following values :
- 1st of july as the "From" date
- the 1st of september as the "To" date.
- rule name as "issuelength"
- rule value as "60"

With this example :
- On the "From" date, any circulation rules will have "issuelength" set to "60".
- After the "To" date, all rules will be set to their previous/normal values.

## Installation
Install the plugin by uploading the KPZ file using the plugin installation form.
Expert mode :
- "git clone" the plugin in a directory
- add the path to the directory as a "plugin_dir" in koha-conf.xml

For the plugin to work you will need to install the following cronjob :
0 0 * * * misc/cronjob/plugins_nightly.pl

This cronjob will run the cronjob method of the plugin everyday and will make the necessary actions.

## how to test the plugin
the easiest way to do it is:
- define the "From" date to today.
- define the rule name to "issuelength" and set a new rule value.
- click "Save configuration"
- manually run misc/cronjob/plugins_nightly.pl.
- check for the effect on the rules.

The plugin also installs a new table to save the previous value.
After the new value is set from the plugin, you can check the previous values are saved in the table "koha_plugin_changeruleswithinperiod_saved_rules_values".

To reverse:
- change the "From" date to a previous date.
- set the "To" date to today.
- save the plugin configuration.
- run misc/cronjob/plugins_nightly.pl.
- check the circulation rules values are back to their normal values.
- you can also check the table "koha_plugin_changeruleswithinperiod_saved_rules_values" is empty

warning : check your test environment date and timezone, you could be surprised!