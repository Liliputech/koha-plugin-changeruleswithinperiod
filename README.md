# Change Rules Within Period

A [Koha](https://koha-community.org) plugin that automatically overrides circulation rules for a defined date range, then restores them afterwards — useful for seasonal loan period adjustments (summer holidays, exam periods, etc.).

---

## Features

- **Date-range rule override** — define a start and end date; on the start date the plugin replaces the chosen circulation rule value with a new one, and after the end date it restores the original values automatically.
- **Any circulation rule** — by default the plugin targets `issuelength`, but any rule name stored in `circulation_rules` can be targeted via the Advanced settings.
- **Ignore zero** — optionally skip rules whose current value is `0` (useful to avoid overriding rules that are intentionally disabled).
- **Per-library configuration** — each branch can have its own independent configuration (date range, rule name, new value). A **Default** configuration targets rules with no branch (`branchcode IS NULL`); library-specific configurations target only that branch.
- **Backup & restore** — original rule values are saved to a dedicated database table before being overridden, and are fully restored after the period ends.
- **Within-period indicator** — the configuration page shows a warning banner and a table of currently backed-up values when the plugin is actively overriding rules.
- **Customizable notification messages** — the warning banner text, the override banner text, and the "check configuration" link label are all editable from the configuration page (shared across all library configurations).
- **Export / Import JSON** — the full plugin configuration (all library configurations + active state) can be exported as a JSON file and imported on another Koha instance.
- **Multilingual** — ships with translations for English (default), French (`fr-FR`), and Swedish (`sv-SE`).
- **Minimum Koha version**: 23.11

---

## How it works

1. A nightly cron job (`misc/cronjob/plugins_nightly.pl`) runs the plugin's `cronjob_nightly` method.
2. For each configured library (including the default), the plugin checks whether today falls within the defined date range.
3. **Entering the period**: the plugin backs up the current values of the targeted rule into the `koha_plugin_changeruleswithinperiod_saved_rules_values` table, then sets all matching rules to the new value.
4. **Leaving the period**: the plugin reads the backed-up values and restores them, then removes the backup records.

The plugin tracks which configurations are actively overriding rules in the `active_configs` plugin data key, so it does not re-apply or re-backup on subsequent nightly runs.

---

## Installation

### From a GitHub Release

Download the latest `.kpz` file from the [Releases](../../releases) page and upload it via **Koha admin → Plugins → Upload plugin**.

### From source (expert mode)

```bash
git clone https://github.com/Liliputech/koha-plugin-changeruleswithinperiod.git /path/to/plugins/
```

Add the directory to `koha-conf.xml`:

```xml
<pluginsdir>/path/to/plugins</pluginsdir>
```

### Cron job (required)

Add the following cron entry to run the plugin logic nightly:

```
0 0 * * * koha-shell <instance> -c "perl misc/cronjobs/plugins_nightly.pl"
```

---

## Configuration

Navigate to **Koha admin → Plugins → Change Rules Within Period → Configure**.

### Library selector

Use the dropdown at the top to choose which configuration you are editing:

- **Default (All Libraries)** — targets circulation rules with `branchcode IS NULL`.
- **A specific branch** — targets only that branch's circulation rules.

Each library configuration is saved and managed independently. Library-specific configurations can be deleted individually; the Default configuration always exists.

### Configuration fields

| Field | Description |
|---|---|
| **From date** | The date on which the rule override is applied. |
| **To date** | The date after which the original rules are restored. |
| **New value** | The value to set for the targeted rule during the period. |
| **Ignore zero** | If checked, rules with a current value of `0` are left untouched. |

### Advanced settings

| Field | Description |
|---|---|
| **Rule name** | The `rule_name` to target in `circulation_rules`. Defaults to `issuelength`. Change this to target a different rule (e.g. `renewalperiod`, `renewalsallowed`). |

### Notification messages

These fields are shared across all library configurations and control the banners displayed on the Koha intranet when the plugin is active:

| Field | Description |
|---|---|
| **Warning message** | Banner text shown when rules *may* be overwritten (i.e. a period is approaching or configured). |
| **Override message** | Banner text shown when rules *are currently* overwritten by the plugin. |
| **Link text** | The label for the link pointing to the plugin configuration page in both banners. |

### Export / Import JSON

- **Export JSON** — downloads the complete plugin configuration (all library configurations and active state) as `changerules-config.json`. Useful for backup or migration.
- **Import JSON** — upload a previously exported JSON file to restore a configuration. The imported data overwrites the current plugin configuration.

---

## Testing

1. Set **From date** to today.
2. Set **New value** to a test value (e.g. `60`).
3. Click **Save configuration**.
4. Run the cron job manually:
   ```bash
   perl misc/cronjobs/plugins_nightly.pl
   ```
5. Check that the relevant `circulation_rules` rows now have `rule_value = 60`.
6. Verify the backup table is populated:
   ```sql
   SELECT * FROM koha_plugin_changeruleswithinperiod_saved_rules_values;
   ```

### Reversing

1. Set **From date** to a past date and **To date** to yesterday.
2. Save and re-run the cron job.
3. Verify that the original values are restored and the backup table is empty.

> ⚠️ Be mindful of your server's timezone — the comparison is done against today's date at midnight.

---

## Releases

Releases are built automatically via GitHub Actions when a version tag (`v*`) is pushed. The `.kpz` artifact is attached to the GitHub Release. There is no need to build the package manually.
