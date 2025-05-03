// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract RealTimeChitFundCommitReveal {
    struct Participant {
        address wallet;
        bool hasReceivedFund;
    }

    struct Bid {
        address bidder;
        uint256 amount; // bid discount
    }

    address public admin;
    uint256 public contributionAmount;
    uint256 public totalParticipants;
    uint256 public currentRound;
    uint256 public roundEndTime;
    uint256 public roundDuration = 3 days;

    IERC20 public token;
    uint256 public registrationFee = 10 * 10 ** 18; // 10 tokens (assuming 18 decimals)

    Participant[] public participants;
    mapping(address => bool) public hasPaid;

    // Bidding phase (commit-reveal)
    enum FundState {
        Collecting,
        Committing,
        Revealing,
        Disbursed
    }

    FundState public fundState;

    uint256 public commitDeadline;
    uint256 public revealDeadline;
    uint256 public commitDuration = 1 days;
    uint256 public revealDuration = 1 days;

    mapping(address => bytes32) public commitments;
    mapping(address => uint256) public revealedBids;
    Bid[] public validBids;
    mapping(uint256 => address) public roundWinners;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyParticipant() {
        require(isParticipant(msg.sender), "Not a participant");
        _;
    }

    constructor(address _tokenAddress, uint256 _contributionAmount, uint256 _totalParticipants) {
        admin = msg.sender;
        token = IERC20(_tokenAddress);
        contributionAmount = _contributionAmount;
        totalParticipants = _totalParticipants;
        currentRound = 1;
        fundState = FundState.Collecting;
        roundEndTime = block.timestamp + roundDuration;
    }

    function join() external {
        require(participants.length < totalParticipants, "Limit reached");

        require(!isParticipant(msg.sender), "Already joined");

        require(token.transferFrom(msg.sender, admin, registrationFee), "Token transfer failed");
        participants.push(Participant(msg.sender, false));
    }

    function contribute() external payable onlyParticipant {
        require(fundState == FundState.Collecting, "Not collecting");
        require(msg.value == contributionAmount, "Incorrect amount");
        require(!hasPaid[msg.sender], "Already paid");

        hasPaid[msg.sender] = true;

        if (allPaid()) {
            fundState = FundState.Committing;
            commitDeadline = block.timestamp + commitDuration;
        }
    }

    function commitBid(bytes32 commitment) external onlyParticipant {
        //commitment is the hash of bit and the secret
        require(fundState == FundState.Committing, "Not in commit phase");
        require(block.timestamp <= commitDeadline, "Commit phase ended");
        commitments[msg.sender] = commitment;
    }

    function startRevealPhase() external onlyAdmin {
        //called manulaly by the admin after the commit duration
        require(fundState == FundState.Committing, "Not in commit phase");
        require(block.timestamp > commitDeadline, "Commit phase not ended");
        fundState = FundState.Revealing;
        revealDeadline = block.timestamp + revealDuration;
    }

    function revealBid(uint256 bidAmount, string calldata salt) external onlyParticipant {
        require(fundState == FundState.Revealing, "Not in reveal phase");
        require(block.timestamp <= revealDeadline, "Reveal phase ended");

        bytes32 expected = keccak256(abi.encodePacked(bidAmount, salt));
        require(commitments[msg.sender] == expected, "Commitment mismatch");

        revealedBids[msg.sender] = bidAmount;
        validBids.push(Bid(msg.sender, bidAmount));
    }

    function disburse() external onlyAdmin {
        require(fundState == FundState.Revealing, "Not in reveal phase");
        require(block.timestamp > revealDeadline, "Reveal phase not ended");
        require(validBids.length > 0, "No valid bids");

        // Find lowest bid
        Bid memory lowest = validBids[0];
        for (uint256 i = 1; i < validBids.length; i++) {
            if (validBids[i].amount < lowest.amount) {
                lowest = validBids[i];
            }
        }

        roundWinners[currentRound] = lowest.bidder;
        payable(lowest.bidder).transfer(address(this).balance - lowest.amount);

        // Reset for next round
        currentRound++;
        fundState = FundState.Collecting;
        roundEndTime = block.timestamp + roundDuration;

        delete validBids;
        resetPayments();
        resetCommitments();
    }

    function resetPayments() internal {
        for (uint256 i = 0; i < participants.length; i++) {
            hasPaid[participants[i].wallet] = false;
        }
    }

    function resetCommitments() internal {
        for (uint256 i = 0; i < participants.length; i++) {
            commitments[participants[i].wallet] = 0;
            revealedBids[participants[i].wallet] = 0;
        }
    }

    function isParticipant(address user) public view returns (bool) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].wallet == user) return true;
        }
        return false;
    }

    function allPaid() public view returns (bool) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (!hasPaid[participants[i].wallet]) return false;
        }
        return true;
    }

    receive() external payable {}
}
