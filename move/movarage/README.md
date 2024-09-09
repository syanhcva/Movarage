# Movarage modules

## TODO

- [ ] Support admin to close position
- [ ] Emit events
- [ ] Support users to adjust position

## Development

### Local build

```sh
aptos move compile --named-addresses movarage=0x0,simple_lending=0x200
# or run without fetch git deps to speed up process
aptos move test --named-addresses movarage=0x0,simple_lending=0x200 --skip-fetch-latest-git-deps
```

### Running test

**Note:** To run test, please follow the instruction in the beginning of `mosaic_mock.move` file.

```sh
aptos move test --named-addresses movarage=0x0,simple_lending=0x200
# or run without fetch git deps to speed up process
aptos move test --named-addresses movarage=0x0,simple_lending=0x200 --skip-fetch-latest-git-deps
```

### Compile and publish

```sh
aptos move compile --named-addresses movarage=0x47a117902a908386980b03ebcbbe4f8eba95719aaf8ce094d873900fb5172ef9 --included-artifacts none
```

```sh
aptos move deploy-object --address-name movarage --profile default-movement-aptos --included-artifacts none

aptos move deploy-object --address-name movarage --profile default-movement-aptos --included-artifacts none --assume-yes
```

```sh
aptos move upgrade-object --address-name movarage --object-address 0xbf01e2efe85ce75b15c6378483b7f9c0c497a48dd57a559182ebb4388b5e91ce --profile default-movement-aptos --included-artifacts none --skip-fetch-latest-git-deps --assume-yes
```