// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Item} from "../src/Item.sol";

/// @dev Test-only stand-in for an immediate deployer holding and distributing the supply.
contract ItemFactoryFixture {
    function deploy() external returns (Item) {
        return new Item();
    }

    function deployDeterministic(bytes32 salt) external returns (Item) {
        return new Item{salt: salt}();
    }

    function send(Item token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract ItemTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Item internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Item();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "Item");
        assertEq(token.symbol(), "ITEM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        Item fresh = new Item();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesSupplyInsteadOfTransactionOrigin() public {
        ItemFactoryFixture factory = new ItemFactoryFixture();
        vm.prank(alice, alice);
        Item fresh = factory.deploy();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_Create2DeploymentNeedsNoArgumentsOrInitialization() public {
        ItemFactoryFixture factory = new ItemFactoryFixture();
        bytes32 salt = keccak256("item deployment test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Item).creationCode))
                    )
                )
            )
        );
        Item fresh = factory.deployDeterministic(salt);
        assertEq(address(fresh), predicted);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_LaunchAllocationsClaimsAndPoolTransfersArriveWhole() public {
        ItemFactoryFixture factory = new ItemFactoryFixture();
        Item fresh = factory.deploy();
        address distributor = makeAddr("distributor fixture");
        address pool = makeAddr("pool custody fixture");
        address requester = makeAddr("requester fixture");
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY * 8 / 10;
        assertTrue(factory.send(fresh, distributor, swarm));
        assertTrue(factory.send(fresh, pool, liquidity));
        assertTrue(factory.send(fresh, requester, SUPPLY - swarm - liquidity));
        assertEq(fresh.balanceOf(address(factory)), 0);
        assertEq(fresh.balanceOf(distributor), swarm);
        assertEq(fresh.balanceOf(pool), liquidity);
        assertEq(fresh.balanceOf(requester), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(fresh.transfer(alice, swarm));
        assertEq(fresh.balanceOf(alice), swarm);
        assertEq(fresh.balanceOf(distributor), 0);

        // Token custody legs only; actual AMM execution belongs to the protected integration test.
        vm.prank(pool);
        assertTrue(fresh.transfer(bob, 123 ether));
        assertEq(fresh.balanceOf(bob), 123 ether);
        vm.prank(bob);
        assertTrue(fresh.transfer(pool, 123 ether));
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(pool), liquidity);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferInsufficientBalanceRevertsWithoutMutation() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferToZeroRevertsForZeroAndPositiveAmounts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventWithoutMovingFunds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 321 ether);
        assertTrue(token.approve(spender, 321 ether));
        assertEq(token.allowance(address(this), spender), 321 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApprovalReplacesRatherThanAddsAndCanBeRevoked() public {
        token.approve(spender, 100);
        assertTrue(token.approve(spender, 7));
        assertEq(token.allowance(address(this), spender), 7);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveZeroSpenderRevertsForZeroAndPositiveAmounts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_ApprovalsAreIsolatedByOwnerAndSpender() public {
        token.approve(spender, 100);
        token.approve(bob, 200);
        vm.prank(alice);
        token.approve(spender, 300);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.allowance(address(this), bob), 200);
        assertEq(token.allowance(alice, spender), 300);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_TransferFromConsumesFiniteAllowanceAndOnlyEmitsTransfer() public {
        token.approve(spender, 100);
        vm.recordLogs();
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), 40);
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40);
        assertEq(token.balanceOf(alice), 40);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ExhaustedAllowanceCannotBeReused() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_InfiniteAllowanceDoesNotDecrease() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 50));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 50));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 50);
        assertEq(token.balanceOf(bob), SUPPLY - 50);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromWithoutAllowanceSucceeds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 40));
        assertEq(token.allowance(address(this), spender), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_OwnerCallingTransferFromAlsoNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientAllowanceIsAtomic() public {
        token.approve(spender, 3);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 3, 4));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 4);
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 5);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5, 6));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 5);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroRecipientRestoresAllowance() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroOwnerRevertsEvenForZeroAmount() public {
        // OZ validates the allowance owner before attempting the underlying transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NeitherDeployerNorStrangerHasMintBurnFreezeOrUpgradePowers() public {
        token.transfer(alice, 100);
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "setMinter(address)",
            "initialize(address)",
            "upgradeTo(address)",
            "setTransfersEnabled(bool)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, 100);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(bob);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100);
        }
        // The deployer cannot take back a holder's tokens or block their transfers.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_RuntimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory code = address(token).code;
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }

    function test_DirectEtherPaymentIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferAboveBalanceReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_TransferFromConsumesOnlyAmountSpent(uint256 rawApproval, uint256 rawSpend) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawSpend, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceCannotMoveFunds(uint256 rawApproval) public {
        uint256 approved = bound(rawApproval, 0, SUPPLY - 1);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approved + 1);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_FailedTransferFromRestoresAllowance(uint256 rawBalance) public {
        uint256 held = bound(rawBalance, 0, SUPPLY - 1);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, held + 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, held + 1);
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApproveReplacesAnyPreviousValue(uint256 first, uint256 second) public {
        token.approve(spender, first);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }
}
