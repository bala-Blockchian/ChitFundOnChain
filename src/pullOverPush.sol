// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract RealTimeChitFund {
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

    IERC20 public token; // Custom token interface
    uint256 public registrationFee = 10 * 10 ** 18; // 10 tokens (assuming 18 decimals)

    Participant[] public participants;
    mapping(address => bool) public hasPaid;
    Bid[] public bids;
    mapping(uint256 => address) public roundWinners;
    mapping(address => bool) public claimed; // Track who has claimed their funds

    enum FundState {
        Collecting,
        Bidding,
        Disbursed
    }

    FundState public fundState;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyParticipant() {
        require(isParticipant(msg.sender), "Not a participant");
        _;
    }

    constructor(address _token, uint256 _contributionAmount, uint256 _totalParticipants) {
        admin = msg.sender;
        token = IERC20(_token);
        contributionAmount = _contributionAmount;
        totalParticipants = _totalParticipants;
        currentRound = 1;
        fundState = FundState.Collecting;
        roundEndTime = block.timestamp + roundDuration;
    }

    // Join function with token payment
    function join() external {
        require(participants.length < totalParticipants, "Limit reached");
        require(!isParticipant(msg.sender), "Already joined");

        // Transfer registration fee to admin
        require(token.transferFrom(msg.sender, admin, registrationFee), "Token transfer failed");

        participants.push(Participant(msg.sender, false));
    }

    // Participants contribute Ether
    function contribute() external payable onlyParticipant {
        require(fundState == FundState.Collecting, "Not collecting");
        require(msg.value == contributionAmount, "Incorrect amount");
        require(!hasPaid[msg.sender], "Already paid");
        hasPaid[msg.sender] = true;

        // Automatically move to bidding if all paid
        if (allPaid()) {
            fundState = FundState.Bidding;
        }
    }

    // Place a bid with discount
    function placeBid(uint256 discount) external onlyParticipant {
        require(fundState == FundState.Bidding, "Not in bidding");
        require(hasPaid[msg.sender], "Pay first");
        bids.push(Bid(msg.sender, discount));
    }

    // Admin disburses funds and sets winner, no transfer yet
    function disburse() external onlyAdmin {
        require(fundState == FundState.Bidding, "Not ready");
        require(bids.length > 0, "No bids");

        // Find lowest bidder
        Bid memory lowest = bids[0];
        for (uint256 i = 1; i < bids.length; i++) {
            if (bids[i].amount < lowest.amount) {
                lowest = bids[i];
            }
        }

        // Set the round winner
        roundWinners[currentRound] = lowest.bidder;

        // Reset for the next round
        currentRound++;
        fundState = FundState.Collecting;
        roundEndTime = block.timestamp + roundDuration;
        delete bids;
        resetPayments();
    }

    // Participants can claim their funds after the round ends
    function claimFunds() external onlyParticipant {
        require(fundState == FundState.Disbursed, "Funds not disbursed yet");
        require(!claimed[msg.sender], "Already claimed");
        require(roundWinners[currentRound] != address(0), "No winner yet");

        uint256 claimAmount = 0;

        if (msg.sender == roundWinners[currentRound]) {
            // Winner gets the discounted amount
            claimAmount = address(this).balance - bids[findWinningBidIndex(msg.sender)].amount;
        } else {
            // Non-winner gets an equal share of remaining funds
            claimAmount = (address(this).balance - bids[findWinningBidIndex(roundWinners[currentRound])].amount)
                / (participants.length - 1);
        }

        // Mark as claimed
        claimed[msg.sender] = true;

        // Transfer funds
        payable(msg.sender).transfer(claimAmount);
    }

    // Helper function to find winner's bid index
    function findWinningBidIndex(address winner) internal view returns (uint256) {
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].bidder == winner) {
                return i;
            }
        }
        revert("Winner's bid not found");
    }

    // Reset participants' payment status for next round
    function resetPayments() internal {
        for (uint256 i = 0; i < participants.length; i++) {
            hasPaid[participants[i].wallet] = false;
        }
    }

    // Helper function to check if a user is a participant
    function isParticipant(address user) public view returns (bool) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i].wallet == user) return true;
        }
        return false;
    }

    // Check if all participants have paid
    function allPaid() public view returns (bool) {
        for (uint256 i = 0; i < participants.length; i++) {
            if (!hasPaid[participants[i].wallet]) return false;
        }
        return true;
    }

    receive() external payable {}
}
