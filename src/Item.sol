// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Item
/// @notice Fixed-supply ERC-20: one billion ITEM, with 18 decimals.
/// @dev The immediate deployer receives the entire supply, including when a factory deploys it.
contract Item is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Item", "ITEM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
