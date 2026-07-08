# bouine documentation

Source for the [bouine](https://github.com/bouine-cache/bouine) documentation site
at **https://bouine.org**.

## Local development

```bash
git clone git@github.com:bouine-cache/bouine-documentation.git
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
