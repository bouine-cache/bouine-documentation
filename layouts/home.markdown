{{ .Title }}

{{ .Content | plainify | replaceRE "\n{3,}" "\n\n" }}