// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test , console} from "forge-std/Test.sol";
import {GToken} from "../src/GToken.sol";
import {RealTimeChitFundCommitReveal} from "../src/RealTimeChitFundCommitReveal.sol";

contract ChitFundTest is Test {
    GToken public grit;
    RealTimeChitFundCommitReveal public chitFund;

    address admin = address(1);
    address p1 = address(2);
    address p2 = address(3);
    address p3 = address(4);

    uint256 public constant CONTRIBUTION = 1 ether;
    uint256 public constant REG_FEE = 10 * 1e18;

    function setUp() public {
        vm.startPrank(admin);
        grit = new GToken();
        chitFund = new RealTimeChitFundCommitReveal(address(grit), CONTRIBUTION, 3);
        vm.stopPrank();

        address[3] memory participants = [p1, p2, p3];

        for (uint256 i = 0; i < 3; i++) {
            grit.mint(participants[i], 100 * 1e18);
            vm.prank(participants[i]);
            grit.approve(address(chitFund), REG_FEE);

            vm.prank(participants[i]);
            chitFund.join();
        }
    }

    function testFullChitFundFlow() public {
        vm.deal(p1, 1 ether);
        vm.deal(p2, 1 ether);
        vm.deal(p3, 1 ether);

        vm.prank(p1);
        chitFund.contribute{value: 1 ether}();

        vm.prank(p2);
        chitFund.contribute{value: 1 ether}();

        vm.prank(p3);
        chitFund.contribute{value: 1 ether}();

        assertEq(uint256(chitFund.fundState()), uint256(RealTimeChitFundCommitReveal.FundState.Committing));

        string memory salt1 = "s1";
        string memory salt2 = "s2";
        string memory salt3 = "s3";

        uint256 b1 = 0.02 ether;
        uint256 b2 = 0.01 ether;
        uint256 b3 = 0.015 ether;

        bytes32 c1 = keccak256(abi.encodePacked(uint256(b1), salt1));
        bytes32 c2 = keccak256(abi.encodePacked(uint256(b2), salt2));
        bytes32 c3 = keccak256(abi.encodePacked(uint256(b3), salt3));

        vm.prank(p1);
        chitFund.commitBid(c1);

        vm.prank(p2);
        chitFund.commitBid(c2);

        vm.prank(p3);
        chitFund.commitBid(c3);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(admin);
        chitFund.startRevealPhase();

        assertEq(uint256(chitFund.fundState()), uint256(RealTimeChitFundCommitReveal.FundState.Revealing));

        vm.prank(p1);
        chitFund.revealBid(b1, salt1);

        vm.prank(p2);
        chitFund.revealBid(b2, salt2);

        vm.prank(p3);
        chitFund.revealBid(b3, salt3);

        uint256 balanceBefore = p2.balance;

        vm.warp(block.timestamp + 2 days);

        vm.prank(admin);
        chitFund.disburse();

        uint256 expected = balanceBefore + 3 ether - b2;
        assertGt(p2.balance, balanceBefore);
        console.log("balance of p2 ", p2.balance);//2.990000000000000000
        assertApproxEqAbs(p2.balance, expected, 2.99e15); // allow tiny delta
    }
}
