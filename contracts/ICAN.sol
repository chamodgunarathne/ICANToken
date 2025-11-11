// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VestingLibrary - Handles vesting calculations
 */
library VestingLibrary {
    struct VestingSchedule {
        uint128 totalAmount;
        uint128 releasedAmount;
        uint64 startTime;
        uint32 duration;
        uint32 cliff;
        bool revoked;
    }

    function calculateVested(
        VestingSchedule memory schedule
    ) internal view returns (uint256) {
        if (schedule.totalAmount == 0 || schedule.revoked)
            return schedule.releasedAmount;
        if (block.timestamp < schedule.startTime + schedule.cliff) return 0;
        if (block.timestamp >= schedule.startTime + schedule.duration)
            return schedule.totalAmount;

        unchecked {
            uint256 elapsed = block.timestamp - schedule.startTime;
            return
                (uint256(schedule.totalAmount) * elapsed) / schedule.duration;
        }
    }

    function getReleasable(
        VestingSchedule memory schedule
    ) internal view returns (uint256) {
        uint256 vested = calculateVested(schedule);
        return
            vested > schedule.releasedAmount
                ? vested - schedule.releasedAmount
                : 0;
    }
}

/**
 * @title StakingLibrary - Handles staking calculations
 */
library StakingLibrary {
    struct StakingInfo {
        uint128 stakedAmount;
        uint64 stakingStartTime;
        uint64 lastRewardClaim;
    }

    uint256 constant MAX_REWARD_PER_CLAIM = 1000000 * 10 ** 18;

    function calculateRewards(
        StakingInfo memory info,
        uint256 rewardRate
    ) internal view returns (uint256) {
        if (info.stakedAmount == 0) return 0;

        unchecked {
            uint256 duration = block.timestamp - info.lastRewardClaim;
            if (duration == 0) return 0;

            uint256 annualReward = (uint256(info.stakedAmount) * rewardRate) /
                1000;
            uint256 rewards = (annualReward * duration) / 365 days;

            return
                rewards > MAX_REWARD_PER_CLAIM ? MAX_REWARD_PER_CLAIM : rewards;
        }
    }
}

/**
 * @title VIPLibrary - Handles VIP level calculations (STAKING ONLY)
 */
library VIPLibrary {
    uint256 constant VIP_LEVEL_1 = 1_000_000 * 10 ** 18;  // 1M ICX staked
    uint256 constant VIP_LEVEL_2 = 5_000_000 * 10 ** 18;  // 5M ICX staked
    uint256 constant VIP_LEVEL_3 = 10_000_000 * 10 ** 18; // 10M ICX staked
    uint256 constant VIP_LEVEL_4 = 50_000_000 * 10 ** 18; // 50M ICX staked

    function calculateLevel(uint256 stakedAmount) internal pure returns (uint8) {
        if (stakedAmount >= VIP_LEVEL_4) return 4;
        if (stakedAmount >= VIP_LEVEL_3) return 3;
        if (stakedAmount >= VIP_LEVEL_2) return 2;
        if (stakedAmount >= VIP_LEVEL_1) return 1;
        return 0;
    }

    function getDiscount(uint8 level) internal pure returns (uint8) {
        if (level == 4) return 50;
        if (level == 3) return 40;
        if (level == 2) return 25;
        if (level == 1) return 10;
        return 0;
    }
}

/**
 * @title ICX Token - iCanX Exchange Token (Secured Version)
 */
contract ICAN is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable  
{
    using VestingLibrary for VestingLibrary.VestingSchedule;
    using StakingLibrary for StakingLibrary.StakingInfo;
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_SUPPLY = 200_000_000 * 10 ** 18;
    uint256 public constant MAX_SUPPLY = 220_000_000  * 10 ** 18;
    uint256 public constant MIN_STAKING_DURATION = 7 days;
    uint256 public constant MAX_STAKING_REWARD_RATE = 1000;

    address public liquidityPool;

    mapping(address => VestingLibrary.VestingSchedule) public vestingSchedules;
    mapping(address => bool) public teamMembers;

    mapping(address => StakingLibrary.StakingInfo) public stakingInfo;
    uint256 public totalStaked;
    uint256 public stakingRewardRate;
    uint256 public totalRewardsMinted;

    mapping(address => uint8) public vipLevels;

    struct Proposal {
        uint128 votesFor;
        uint128 votesAgainst;
        uint64 endTime;
        uint64 createdAt;
        bool executed;
        string description;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => uint256)) public votingPowerSnapshot;
    uint256 public proposalCount;
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant MIN_PROPOSAL_TOKENS = 100_000 * 10 ** 18;
    uint256 public constant QUORUM_PERCENTAGE = 10;

    uint256 public totalBurned;
    address public buybackWallet;

    event TokensStaked(address indexed staker, uint256 amount);
    event TokensUnstaked(address indexed staker, uint256 amount);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event VIPLevelUpdated(address indexed user, uint8 oldLevel, uint8 newLevel);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        string description
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );
    event TokensBuybackAndBurned(uint256 amount);
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 amount,
        uint256 duration,
        uint256 cliff
    );
    event VestingReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 refundAmount);
    event StakingRewardRateUpdated(uint256 oldRate, uint256 newRate);
    event BatchTransferExecuted(
        address indexed sender,
        uint256 recipientCount,
        uint256 totalAmount
    );

    string public constant tokenImageIPFS = "bafkreihd6mjmkoczbz5gpd6u3d2slubw5vv4exbvmp6j5c4rbbvefmrblu";

    function tokenImageURL() public pure returns (string memory) {
        return string(abi.encodePacked("https://ipfs.io/ipfs/", tokenImageIPFS));
    }

    function getTokenMetadata() external pure returns (string memory) {
        return string(abi.encodePacked(
            '{"name":"ICAN",',
            '"symbol":"ICAN",',
            '"decimals":18,',
            '"image":"', tokenImageURL(), '",',
            '"website":"https://icanx.io"}'
        ));
    }

    uint256[50] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __ERC20_init("ICAN", "ICAN");
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _mint(msg.sender, TOTAL_SUPPLY);
        buybackWallet = msg.sender;
        stakingRewardRate = 60; // 6% APY
        proposalCount = 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier onlyTeamMember() {
        require(teamMembers[msg.sender], "Not team member");
        _;
    }

    function transfer(
        address to,
        uint256 value
    ) public override whenNotPaused returns (bool) {
        require(value > 0, "Invalid amount");
        require(to != address(0), "Invalid recipient");

        bool success = super.transfer(to, value);
        if (success) {
            // Only update VIP level for sender (since staking amount might change)
            _updateVIPLevel(msg.sender);
        }
        return success;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override whenNotPaused returns (bool) {
        require(value > 0, "Invalid amount");
        require(to != address(0), "Invalid recipient");

        bool success = super.transferFrom(from, to, value);
        if (success) {
            // Only update VIP level for sender (since staking amount might change)
            _updateVIPLevel(from);
        }
        return success;
    }

    function setLiquidityPool(address _lp) external onlyOwner {
        require(_lp != address(0), "Invalid LP address");
        liquidityPool = _lp;
    }

    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliff
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Invalid amount");
        require(amount <= type(uint128).max, "Amount too large");
        require(
            vestingSchedules[beneficiary].totalAmount == 0,
            "Schedule exists"
        );

        uint256 duration = 10 * 365 days;
        require(cliff <= duration, "Cliff exceeds duration");
        require(cliff <= type(uint32).max, "Cliff too large");

        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, address(this), amount);

        vestingSchedules[beneficiary] = VestingLibrary.VestingSchedule({
            totalAmount: uint128(amount),
            releasedAmount: 0,
            startTime: uint64(block.timestamp),
            duration: uint32(duration),
            cliff: uint32(cliff),
            revoked: false
        });

        teamMembers[beneficiary] = true;
        emit VestingScheduleCreated(beneficiary, amount, duration, cliff);
    }

    function releaseVestedTokens() external nonReentrant {
        VestingLibrary.VestingSchedule storage schedule = vestingSchedules[
            msg.sender
        ];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.revoked, "Schedule revoked");
        require(
            block.timestamp >= schedule.startTime + schedule.cliff,
            "Cliff not reached"
        );

        uint256 releasableAmount = schedule.getReleasable();
        require(releasableAmount > 0, "Nothing to release");

        schedule.releasedAmount = uint128(
            uint256(schedule.releasedAmount) + releasableAmount
        );
        _transfer(address(this), msg.sender, releasableAmount);

        emit VestingReleased(msg.sender, releasableAmount);
    }

    function revokeVesting(address beneficiary) external onlyOwner {
        VestingLibrary.VestingSchedule storage schedule = vestingSchedules[
            beneficiary
        ];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.revoked, "Already revoked");

        uint256 vested = schedule.calculateVested();
        uint256 releasable = vested > schedule.releasedAmount
            ? vested - schedule.releasedAmount
            : 0;

        if (releasable > 0) {
            schedule.releasedAmount = uint128(
                uint256(schedule.releasedAmount) + releasable
            );
            _transfer(address(this), beneficiary, releasable);
        }

        uint256 remaining = uint256(schedule.totalAmount) -
            uint256(schedule.releasedAmount);
        if (remaining > 0) {
            _transfer(address(this), owner(), remaining);
        }

        schedule.revoked = true;
        emit VestingRevoked(beneficiary, remaining);
    }

    function removeTeamMember(address member) external onlyOwner {
        teamMembers[member] = false;
    }

    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        StakingLibrary.StakingInfo storage info = stakingInfo[msg.sender];

        if (info.stakedAmount > 0) {
            _claimStakingRewards(msg.sender, info);
        }

        _transfer(msg.sender, address(this), amount);

        info.stakedAmount = uint128(uint256(info.stakedAmount) + amount);
        if (info.stakingStartTime == 0) {
            info.stakingStartTime = uint64(block.timestamp);
        }
        info.lastRewardClaim = uint64(block.timestamp);

        unchecked {
            totalStaked += amount;
        }

        _updateVIPLevel(msg.sender);
        emit TokensStaked(msg.sender, amount);
    }

    function unstakeTokens(uint256 amount) external nonReentrant whenNotPaused {
        StakingLibrary.StakingInfo storage info = stakingInfo[msg.sender];
        require(info.stakedAmount >= amount, "Insufficient staked");
        require(
            block.timestamp >= info.stakingStartTime + MIN_STAKING_DURATION,
            "Minimum staking duration not met"
        );

        _claimStakingRewards(msg.sender, info);

        unchecked {
            info.stakedAmount = uint128(uint256(info.stakedAmount) - amount);
            totalStaked -= amount;
        }

        if (info.stakedAmount == 0) {
            info.stakingStartTime = 0;
            info.lastRewardClaim = 0;
        }

        _transfer(address(this), msg.sender, amount);
        _updateVIPLevel(msg.sender);
        emit TokensUnstaked(msg.sender, amount);
    }

    function claimStakingRewards() external nonReentrant whenNotPaused {
        _claimStakingRewards(msg.sender, stakingInfo[msg.sender]);
    }

    function _claimStakingRewards(
        address staker,
        StakingLibrary.StakingInfo storage info
    ) private {
        uint256 rewards = info.calculateRewards(stakingRewardRate);
        if (rewards > 0) {
            require(
                totalSupply() + rewards <= MAX_SUPPLY,
                "Exceeds max supply"
            );

            info.lastRewardClaim = uint64(block.timestamp);
            totalRewardsMinted += rewards;
            _mint(staker, rewards);

            emit RewardsClaimed(staker, rewards);
        }
    }

    function _updateVIPLevel(address user) private {
        if (
            user == address(0) || user == address(this) || user == liquidityPool
        ) return;

        // VIP levels now based ONLY on staked amount (not wallet balance)
        uint256 stakedAmount = uint256(stakingInfo[user].stakedAmount);

        uint8 oldLevel = vipLevels[user];
        uint8 newLevel = VIPLibrary.calculateLevel(stakedAmount);

        if (oldLevel != newLevel) {
            vipLevels[user] = newLevel;
            emit VIPLevelUpdated(user, oldLevel, newLevel);
        }
    }

    function getFeeDiscount(address user) external view returns (uint8) {
        return VIPLibrary.getDiscount(vipLevels[user]);
    }

    function distributeTokens(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, to, amount);
        // No VIP update since VIP is staking-only
    }

    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner whenNotPaused {
        uint256 length = recipients.length;
        require(length == amounts.length, "Array length mismatch");
        require(length > 0 && length <= 50, "Batch size: 1-50");

        uint256 senderBalance = balanceOf(msg.sender);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < length; ) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];

            require(recipient != address(0), "Invalid recipient");
            require(
                recipient != address(this),
                "Cannot transfer to token contract"
            );
            require(amount > 0, "Amount must be > 0");

            totalAmount += amount;
            require(totalAmount >= amount, "Total amount overflow");
            require(totalAmount <= senderBalance, "Insufficient balance");

            _transfer(msg.sender, recipient, amount);
            // No VIP update for recipients since VIP is staking-only

            unchecked {
                ++i;
            }
        }

        emit BatchTransferExecuted(msg.sender, length, totalAmount);
    }

    function createProposal(
        string calldata description
    ) external returns (uint256) {
        require(bytes(description).length > 0, "Empty description");
        require(bytes(description).length <= 500, "Description too long");
        require(
            balanceOf(msg.sender) >= MIN_PROPOSAL_TOKENS,
            "Insufficient tokens"
        );

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.description = description;
        proposal.endTime = uint64(block.timestamp + VOTING_DURATION);
        proposal.createdAt = uint64(block.timestamp);
        proposal.votesFor = 0;
        proposal.votesAgainst = 0;
        proposal.executed = false;

        emit ProposalCreated(proposalId, msg.sender, description);
        return proposalId;
    }

    function vote(uint256 proposalId, bool support) external nonReentrant {
        require(
            proposalId > 0 && proposalId < proposalCount,
            "Invalid proposal ID"
        );
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(!proposal.executed, "Already executed");

        // Voting power still includes both balance + staked for governance
        uint256 votingPower = balanceOf(msg.sender) +
            uint256(stakingInfo[msg.sender].stakedAmount);
        require(votingPower > 0, "No voting power");
        require(votingPower <= type(uint128).max, "Voting power overflow");

        proposal.hasVoted[msg.sender] = true;
        votingPowerSnapshot[proposalId][msg.sender] = votingPower;

        unchecked {
            if (support) {
                proposal.votesFor += uint128(votingPower);
            } else {
                proposal.votesAgainst += uint128(votingPower);
            }
        }

        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    function executeProposal(
        uint256 proposalId
    ) external onlyOwner nonReentrant {
        require(
            proposalId > 0 && proposalId < proposalCount,
            "Invalid proposal ID"
        );
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting ongoing");
        require(!proposal.executed, "Already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal failed");

        uint256 totalVotes = uint256(proposal.votesFor) +
            uint256(proposal.votesAgainst);
        uint256 quorum = (totalSupply() * QUORUM_PERCENTAGE) / 100;
        require(totalVotes >= quorum, "Quorum not met");

        proposal.executed = true;
    }

    function getProposalVotes(
        uint256 proposalId
    )
        external
        view
        returns (
            uint128 votesFor,
            uint128 votesAgainst,
            uint64 endTime,
            bool executed
        )
    {
        require(
            proposalId > 0 && proposalId < proposalCount,
            "Invalid proposal ID"
        );
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.votesFor,
            proposal.votesAgainst,
            proposal.endTime,
            proposal.executed
        );
    }

    function hasVoted(
        uint256 proposalId,
        address voter
    ) external view returns (bool) {
        require(
            proposalId > 0 && proposalId < proposalCount,
            "Invalid proposal ID"
        );
        return proposals[proposalId].hasVoted[voter];
    }

    function getProposalDescription(
        uint256 proposalId
    ) external view returns (string memory) {
        require(
            proposalId > 0 && proposalId < proposalCount,
            "Invalid proposal ID"
        );
        return proposals[proposalId].description;
    }

    function buybackAndBurn(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Invalid amount");
        require(
            balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        _burn(address(this), amount);
        unchecked {
            totalBurned += amount;
        }

        emit TokensBuybackAndBurned(amount);
    }

    function setBuybackWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid address");
        buybackWallet = newWallet;
    }

    function setStakingRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= MAX_STAKING_REWARD_RATE, "Rate too high");
        uint256 oldRate = stakingRewardRate;
        stakingRewardRate = newRate;
        emit StakingRewardRateUpdated(oldRate, newRate);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function calculateStakingRewards(
        address user
    ) external view returns (uint256) {
        return stakingInfo[user].calculateRewards(stakingRewardRate);
    }

    function getVestingInfo(
        address beneficiary
    )
        external
        view
        returns (
            uint128 totalAmount,
            uint128 releasedAmount,
            uint64 startTime,
            uint32 duration,
            uint32 cliff,
            uint256 vestedAmount,
            uint256 releasableAmount,
            bool revoked
        )
    {
        VestingLibrary.VestingSchedule memory schedule = vestingSchedules[
            beneficiary
        ];
        uint256 vested = schedule.calculateVested();
        uint256 releasable = schedule.getReleasable();

        return (
            schedule.totalAmount,
            schedule.releasedAmount,
            schedule.startTime,
            schedule.duration,
            schedule.cliff,
            vested,
            releasable,
            schedule.revoked
        );
    }

    function getUserHoldings(
        address user
    )
        external
        view
        returns (
            uint256 walletBalance,
            uint256 stakedBalance,
            uint256 totalHolding,
            uint8 vipLevel
        )
    {
        walletBalance = balanceOf(user);
        stakedBalance = stakingInfo[user].stakedAmount;
        totalHolding = walletBalance + stakedBalance;
        vipLevel = vipLevels[user];
    }

    function getStakingInfo(
        address user
    )
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 stakingStartTime,
            uint256 lastRewardClaim,
            uint256 pendingRewards,
            bool canUnstake
        )
    {
        StakingLibrary.StakingInfo memory info = stakingInfo[user];
        stakedAmount = info.stakedAmount;
        stakingStartTime = info.stakingStartTime;
        lastRewardClaim = info.lastRewardClaim;
        pendingRewards = info.calculateRewards(stakingRewardRate);
        canUnstake =
            block.timestamp >= info.stakingStartTime + MIN_STAKING_DURATION;
    }

    function getVIPThresholds() external pure returns (uint256[4] memory) {
        return [
            VIPLibrary.VIP_LEVEL_1,
            VIPLibrary.VIP_LEVEL_2,
            VIPLibrary.VIP_LEVEL_3,
            VIPLibrary.VIP_LEVEL_4
        ];
    }

    function getFeeDiscounts() external pure returns (uint8[4] memory) {
        return [uint8(10), 25, 40, 50];
    }

    function recoverERC20(
        address tokenAddress,
        uint256 tokenAmount
    ) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover ICX");
        require(tokenAddress != address(0), "Invalid token address");

        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner().call{value: balance}("");
            require(success, "Transfer failed");
        }
    }

    receive() external payable {}
}