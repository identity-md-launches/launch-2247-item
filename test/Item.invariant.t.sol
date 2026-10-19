// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Item} from "../src/Item.sol";

/// @dev Test-only reference ledger. Bounds come from this model, not token storage.
/// Failed calls leave the model unchanged; invariants therefore check rollback as well as success.
contract ItemHandler is Test {
    Item internal immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Item token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant actor ", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, 0, allowed < held ? allowed : held);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    /// @dev Explicitly reach revocation, dust, balance-sized and maximum allowances in sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[7] memory values = [
            uint256(0),
            1,
            expectedBalance[owner],
            1_000_000_000 * 10 ** 18,
            1_000_000_000 * 10 ** 18 + 1,
            type(uint256).max - 1,
            type(uint256).max
        ];
        _approve(owner, spender, values[mode % values.length]);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function rejectTransferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        // Unlimited approval has no representable overspend; revoke it before this attempt.
        if (allowed == type(uint256).max) {
            _approve(from, spender, 0);
            allowed = 0;
        }
        uint256 amount = bound(amountSeed, allowed + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectTransferFromAboveBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        // Reach the balance check, including the path that first deducts a finite allowance.
        if (expectedAllowance[from][spender] < amount) {
            _approve(from, spender, amount);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(spender);
        token.transferFrom(from, to, amount);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        mode %= 3;
        if (mode == 0) {
            uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (mode == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amountSeed);
        } else {
            uint256 allowed = expectedAllowance[owner][spender];
            uint256 held = expectedBalance[owner];
            uint256 amount = bound(amountSeed, 0, allowed < held ? allowed : held);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }
}

/// @dev Expected token reverts are caught by handlers. Every unexpected revert/assertion must fail the campaign.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract ItemInvariantTest is StdInvariant, Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Item internal token;
    ItemHandler internal handler;

    function setUp() public {
        token = new Item();
        handler = new ItemHandler(token);
        token.transfer(handler.actors(0), SUPPLY);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = ItemHandler.transfer.selector;
        selectors[1] = ItemHandler.approve.selector;
        selectors[2] = ItemHandler.transferFrom.selector;
        selectors[3] = ItemHandler.approveBoundary.selector;
        selectors[4] = ItemHandler.rejectTransferAboveBalance.selector;
        selectors[5] = ItemHandler.rejectTransferFromAboveAllowance.selector;
        selectors[6] = ItemHandler.rejectTransferFromAboveBalance.selector;
        selectors[7] = ItemHandler.rejectZeroAddress.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyIsFixedAndConserved() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_BalancesMatchReferenceLedger() public view {
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor));
        }
    }

    function invariant_AllowancesMatchReferenceLedger() public view {
        for (uint256 i; i < 5; ++i) {
            assertEq(token.allowance(handler.actors(i), address(0)), 0);
            assertEq(token.allowance(address(0), handler.actors(i)), 0);
            for (uint256 j; j < 5; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "Item");
        assertEq(token.symbol(), "ITEM");
        assertEq(token.decimals(), 18);
    }

    /// @dev Every sequence must leave holders able to move their whole balance, including dust.
    function afterInvariant() public {
        address recipient = handler.actors(0);
        for (uint256 i = 1; i < 5; ++i) {
            address actor = handler.actors(i);
            uint256 amount = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(actor), 0);
        }
        assertEq(token.balanceOf(recipient), SUPPLY);
        vm.prank(recipient);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
