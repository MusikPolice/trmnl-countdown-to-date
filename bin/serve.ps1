docker run --rm -it `
  --publish 4567:4567 `
  --volume "${PWD}:/plugin" `
  trmnl/trmnlp serve
