# Piano

## Development

Run the app with `bin/dev` or `docker compose up`. Rails UI uses the Hound theme
and provides sample pages at `/railsui` and `/rui/dashboard`.

Rails UI configuration is in `config/railsui.yml`. The generated sample pages
and theme assets can be customized in `app/views/rui` and
`app/assets/stylesheets/railsui`.

The Tools page converts score PDFs to compressed MusicXML (`.mxl`) locally with
Audiveris 5.11.0 (AGPL-3.0). The Docker images install Audiveris for this tool.
