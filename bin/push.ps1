docker run --rm -it `
  --volume "$env:USERPROFILE\.config\trmnlp:/root/.config/trmnlp" `
  --volume "${PWD}:/plugin" `
  trmnl/trmnlp push
