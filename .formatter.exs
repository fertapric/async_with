[
  inputs: [
    "mix.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],
  locals_without_parens: [
    async: 2
  ],
  export: [
    locals_without_parens: [async: 2]
  ]
]
