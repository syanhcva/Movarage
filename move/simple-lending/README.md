
## Compile and publish

- Please change the values of address and profile to yours appropriate values.
- Could remove `--skip-fetch-latest-git-deps` options if you want.

```sh
aptos move compile --named-addresses simple_lending=0x47a117902a908386980b03ebcbbe4f8eba95719aaf8ce094d873900fb5172ef9  --included-artifacts none --skip-fetch-latest-git-deps
```

```sh
aptos move deploy-object --address-name simple_lending --profile default-movement-aptos --included-artifacts none --skip-fetch-latest-git-deps
```

```sh
aptos move upgrade-object --address-name simple_lending --object-address 0xa0fd52f02567234b1a743e823214c81d659090de1eb3da5e305114fdaa76159e --profile default-movement-aptos --included-artifacts none --skip-fetch-latest-git-deps --assume-yes
```

- Resource account: 0x4eeffad0f15f3265cae46463b776ddf148555b7f292924014c11efbf3dba37a4