# Vendored dependencies

These are ordinary source files, with no submodules or package-install step.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0) | v5.4.0 | ERC20 and its four transitive Solidity dependencies | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | v1.9.7 | `src/`, test support only | MIT or Apache-2.0 |

The Solidity files are unmodified upstream sources. Each dependency's license is
included alongside its sources. `SHA256SUMS` records the SHA-256 of every vendored
source and license; check it from the project root with `sha256sum -c lib/SHA256SUMS`.
No network is needed to resolve imports or run the tests.
