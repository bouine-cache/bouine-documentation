# bouine documentation

Source for the [bouine](https://github.com/thylong/bouine) documentation site
at **https://bouine.thylong.com**.

## Local development

```bash
git clone git@github.com:thylong/bouine-documentation.git
cd bouine-documentation
git submodule update --init
npm install
make serve     # -> http://localhost:1313
```

## Build

```bash
make build     # -> ./public/
```

## License

Code (Hugo configuration, templates, assets) is licensed under
[Apache 2.0](LICENSE). Content (Markdown under `content/`) is licensed under
[CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). The theme
(`themes/doks`) is MIT.
