// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Item} from "src/Item.sol";

/// @notice Boundary and sequence tests extending the deployment and ERC-20 tests in Item.t.sol.
/// forge-config: default.fuzz.runs = 1000
contract ItemBoundaryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Item internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    function setUp() public {
        token = new Item();
        alice = makeAddr("boundary alice");
        bob = makeAddr("boundary bob");
        spender = makeAddr("boundary spender");
    }

    function test_OneBaseUnitCanBeTransferredAndSpentPrecisely() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferAmountRevertsWithoutOverflow() public {
        bytes memory error = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(error);
        token.transfer(alice, type(uint256).max);

        token.approve(spender, type(uint256).max);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsSpentAndNotTreatedAsUnlimited() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedAllowanceCanBeReducedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        token.approve(spender, type(uint256).max);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalCanPrecedeFundingButCannotCreateTokens() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, SUPPLY));
        vm.prank(spender);
        token.transferFrom(alice, bob, SUPPLY);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);

        assertTrue(token.transfer(alice, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_AllowanceBelongsToCallerNotTransactionOrigin() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob, spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender, bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_SelfApprovedSelfTransferConsumesOnlyAllowance() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(alice, 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, alice, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroRecipientRejectsZeroSpendWithUnlimitedAllowance() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceLifecycleSurvivesEmptyBalance(uint256 rawHeld) public {
        uint256 held = bound(rawHeld, 1, SUPPLY - 1);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, held));
        assertEq(token.allowance(alice, spender), SUPPLY - held);
        assertEq(token.balanceOf(alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), SUPPLY - held);
        assertEq(token.balanceOf(bob), held);

        token.transfer(alice, SUPPLY - held);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, SUPPLY - held));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TwoSpendersCannotConsumeEachOthersAllowance(uint256 rawFirst, uint256 rawSecond) public {
        uint256 first = bound(rawFirst, 1, SUPPLY - 1);
        uint256 second = bound(rawSecond, 1, SUPPLY - first);
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(spender, first);
        vm.prank(alice);
        token.approve(bob, second);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, first));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, bob), second);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, bob), second);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, address(this), second));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), SUPPLY - first - second);
        assertEq(token.balanceOf(bob), first);
        assertEq(token.balanceOf(address(this)), second);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripsPreserveBalancesAndAllowances(
        uint256 rawAmount,
        uint8 rawCycles,
        uint256 approved
    ) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 cycles = bound(uint256(rawCycles), 1, 8);
        token.approve(spender, approved);
        for (uint256 i; i < cycles; ++i) {
            assertTrue(token.transfer(alice, amount));
            assertEq(token.balanceOf(alice), amount);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.allowance(address(this), spender), approved);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_ZeroRecipientFailurePreservesAnyAllowance(uint256 approved, uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, approved < SUPPLY ? approved : SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FiniteSelfTransferFromSpendsOnlyAuthorization(
        uint256 rawApproval,
        uint256 rawSpend,
        bool ownerIsSpender
    ) public {
        uint256 approved = bound(rawApproval, 0, type(uint256).max - 1);
        uint256 amount = bound(rawSpend, 0, approved < SUPPLY ? approved : SUPPLY);
        address caller = ownerIsSpender ? address(this) : spender;
        token.approve(caller, approved);
        vm.prank(caller);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.allowance(address(this), caller), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalsDoNotReserveOrFreezeBalance(uint256 approved) public {
        token.approve(spender, approved);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        bytes memory error = approved == 0
            ? abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1);
        vm.expectRevert(error);
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
