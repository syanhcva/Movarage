# Movarage modules

## Development

### Local build

```sh
aptos move compile --named-addresses movarage=0x0,aggregator_caller=0x0,simple_lending=0x200
# or run without fetch git deps to speed up process
aptos move test --named-addresses movarage=0x0,aggregator_caller=0x0,simple_lending=0x200 --skip-fetch-latest-git-deps
```

### Running test

**Note:** To run test, please follow the instruction in the beginning of `mosaic_mock.move` file.

```sh
aptos move test --named-addresses movarage=0x0,aggregator_caller=0x0,simple_lending=0x200
# or run without fetch git deps to speed up process
aptos move test --named-addresses movarage=0x0,aggregator_caller=0x0,simple_lending=0x200 --skip-fetch-latest-git-deps
```