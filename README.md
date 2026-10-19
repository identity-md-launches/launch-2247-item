# Item (ITEM)

`src/Item.sol:Item` is a fixed-supply ERC-20. It mints exactly
**1,000,000,000 ITEM** once, in its constructor, to the immediate deployer
(`msg.sender`). It uses the vendored OpenZeppelin Contracts v5.4.0 ERC20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract | `Item` |
| Name | `Item` |
| Symbol | `ITEM` |
| Decimals | `18` |
| Total supply, base units | `1000000000000000000000000000` (`10**27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10**18` |
| Constructor arguments | None; ABI argument list `[]` |
| Initial recipient | Immediate deploying account or factory |
| Target launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The brief specifies a plain token, so transfers have no fee, tax, burn, restrictions,
or external callbacks. Every successful transfer delivers the exact requested amount.
There is no owner, minter, pause, blacklist, seizure, upgrade, or post-deployment mint
or burn entry point. Supply stays constant for the lifetime of the deployment.

Standard ERC-20 `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, and
`totalSupply` are available, plus metadata. Amounts are base units: one ITEM is
`10**18` units. Transfers return `true` on success and revert with ERC-6093 custom
errors for insufficient balance/allowance or invalid zero addresses. Zero-amount
transfers between valid addresses and transfers to oneself are allowed and emit
`Transfer`. A zero-address spender is rejected even for a zero approval.

Approvals replace the caller's prior allowance and emit `Approval`. Finite allowances
decrease on `transferFrom`; `type(uint256).max` represents an unlimited allowance and
does not decrease. OpenZeppelin v5 does not emit an additional `Approval` event when
an allowance is consumed. A failed transfer rolls back the allowance change.
`transferFrom` requires allowance even when the caller is the sender.

## Build and test

Prerequisites are Foundry and Solidity **0.8.26**, already installed for offline use.
The configuration pins that compiler, the Cancun EVM, optimization at 200 runs,
and `bytecode_hash = "none"`. Dependencies are included in `lib/` with licenses
and checksums; no downloads, environment configuration, RPC, FFI, or filesystem
cheatcode permissions are needed for the tests.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x5bc181e3da6850f5871e0e09a449c556c9e8e45b28794b707fe5db687ea16d8c forge test
forge fmt --check
```

Tests cover constructor metadata/supply/events, direct and factory deployment,
exact launch allocation transfers, successful and failing ERC-20 operations,
zero values/addresses, self-transfers, allowance replacement/revocation, infinite
approvals, failure atomicity, missing administrative powers, and runtime opcodes.
Fuzz tests exercise balances and allowances; stateful invariants exercise sequences
of transfers, approvals, and delegated transfers while checking supply conservation
and an independent balance/allowance model.

## Deployment and operations

Deploy the creation bytecode for `src/Item.sol:Item` with **no arguments and no ETH**.
There are no linked libraries, initialization calls, external dependencies, or admin
settings. This constructor works on an empty chain and also through CREATE2.
When a factory deploys, the factory receives the entire supply; an intermediary
deployment helper would receive it instead. The originator of the transaction has
no special status. The authorized launch service must use the intended factory
and handle its outgoing allocation transfers.

The supplied launch policy assigns 10% (100,000,000 ITEM) to its distributor,
80% (800,000,000 ITEM) to liquidity, and the remaining 10% (100,000,000 ITEM)
to the requester's recipient `0x18e0a43cb0236c3e2e6f6f229fc2ca36299a4636`.
These are factory operations after deployment, not token constructor allocations.
The launch service owns the ETH pool configuration (fee `12500`, tick spacing `60`)
and the initial capitalization of `10000000000000000000` wei (10 ETH).
No address or economics setting is embedded in the token. The separate manifest
step supplies `launch.json`; this project does not create one.

### After launch

There are no owner-settable values or maintenance calls. The launch operator is
responsible for deploying the reviewed artifact, verifying its source, checking
metadata and the full constructor allocation, and completing the launch's
distribution and pool operations. Holders manage their keys and allowances;
prefer exact approvals, and revoke an existing approval to zero before replacing
it if a spender could race the change. The token cannot recover assets accidentally
sent to its own address or an unintended recipient and cannot reverse transfers.
It has no payable entry point or asset rescue function.

Validation uses local unit, fuzz, and stateful invariant tests plus a manual review
against the supplied security reference. The supplied protected integration tests
depend on the launch infrastructure and manifest, which are not part of this empty
project; local tests check their token-side requirements, and the network verifier
runs the full launch checks. Slither and Mythril were not run. Testing is not an
independent security audit; independent review and deployment are the launch
process's responsibilities. No transactions are broadcast by this project.
