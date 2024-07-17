// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IWhitelist.sol";


contract poolToken is ERC20 {
    address public poolAddress;
    constructor(
        string memory name,
        string memory symbol,
        address _poolAddress
    ) ERC20(name, symbol) {
        poolAddress = _poolAddress;
    }

    modifier onlyPool() {
        require(
            msg.sender == poolAddress,
            "Only the Pool contract can call this function"
        );
        _;
    }

    function mint(address to, uint256 amount) external onlyPool {
        _mint(to, amount);
    }
}

contract Tokenpool is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    struct Pool {
        string name;
        string symbol;
        uint256 deadline;
        uint256 duration;
        uint256 maxParticipants;
        uint256 currentParticipants;
        address tokenAddress;
        bool useWhitelist;
        uint256 totalStaked;
        uint256 totalSupply;
        uint256 totalScore;
        uint256 whitelistIndex;
    }

    uint256 public poolCount;
    uint256 public totalStakeScore;
    mapping(address => uint256) public userTotalStakeScore;
    mapping(uint256 => uint256) public miniStakeValues;
    mapping(uint256 => uint256) public maxStakeValues;
    mapping(uint256 => Pool) public pools;
    mapping(address => mapping(uint256 => uint256)) public userStakes;
    mapping(address => mapping(uint256 => uint256)) public userScores;
    mapping(address => mapping(uint256 => bool)) public hasClaimed;
    address public  feeRecipient;
    address public  airdropContract;
    IWhitelist public  whitelistContract;
    address public votingContract;

    event PoolCreated(
        uint256 poolId,
        string name,
        string symbol,
        uint256 totalSupply,
        address poolCreater,
        uint256 deadLine,
        bool useWhitelist,
        uint256 miniStakeValue,
        uint256 maxStakeValue,
        uint256 whitelistIndex
    );
    event TokenDeployed(uint256 poolId, address tokenAddress);
    event Stake(
        address staker,
        uint256 poolId,
        uint256 amount,
        uint256 rank,
        uint256 userScore
    );
    event Unstake(address staker, uint256 poolId, uint256 amount);
    event Claim(address claimer, uint256 poolId, uint256 amount);

    function setVotingContract(address _votingContract) external {
        require(votingContract == address(0), "already set");
        votingContract = _votingContract;
    }

    function initialize(
        address _feeRecipient,
        address _votingContract,
        address _airdropContract,
        address _whitelistContract,
        address _admin
    ) initializer public {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();

        feeRecipient = _feeRecipient;
        votingContract = _votingContract;
        airdropContract = _airdropContract;
        whitelistContract = IWhitelist(_whitelistContract);
    }

    modifier onlyVotingContract() {
        require(
            msg.sender == votingContract,
            "Only the votingContract can call"
        );
        _;
    }

    function createPool(
        string calldata name,
        string calldata symbol,
        uint256 duration,
        uint256 totalSupply,
        uint256 maxParticipants,
        uint256 miniStakeValue,
        uint256 maxStakeValue,
        uint256 whitelistIndex,
        bool useWhitelist
    ) external onlyVotingContract {
        poolCount++;
        Pool storage new_pool = pools[poolCount];
        new_pool.name = name;
        new_pool.symbol = symbol;
        new_pool.duration = duration;
        new_pool.deadline = block.timestamp + duration;
        new_pool.totalSupply = totalSupply;
        new_pool.useWhitelist = useWhitelist;
        new_pool.maxParticipants = maxParticipants;
        new_pool.whitelistIndex = whitelistIndex;
        miniStakeValues[poolCount] = miniStakeValue;
        maxStakeValues[poolCount] = maxStakeValue;

        emit PoolCreated(
            poolCount,
            name,
            symbol,
            totalSupply,
            msg.sender,
            new_pool.deadline,
            useWhitelist,
            miniStakeValue,
            maxStakeValue,
            whitelistIndex
        );
    }

    function stake(uint256 poolId) external payable {
        require(msg.value >= miniStakeValues[poolId] && msg.value <= maxStakeValues[poolId], "Invalid amount");
        Pool storage pl = pools[poolId];
        require(block.timestamp < pl.deadline, "Pool staking period has ended");
        require(
            userStakes[msg.sender][poolId] == 0,
            "User has  stakes in this Pool"
        );
        require(
            pl.currentParticipants + 1 <= pl.maxParticipants,
            "Maximum participants reached"
        );

        pl.totalStaked += msg.value;
        userStakes[msg.sender][poolId] += msg.value;
        totalStakeScore += msg.value;
        userTotalStakeScore[msg.sender] += msg.value;
        pl.currentParticipants++;
        // caculate score
        uint256 timeFactor = pl.deadline - block.timestamp;
        uint256 participantFactor = pl.maxParticipants +
            1 -
            pl.currentParticipants;
        uint256 userScore = (timeFactor * participantFactor * msg.value) /
            (pl.duration * pl.maxParticipants);
        userScores[msg.sender][poolId] = userScore;
        pl.totalScore += userScore;

        emit Stake(
            msg.sender,
            poolId,
            msg.value,
            pl.currentParticipants,
            userScore
        );
    }

    function unstake(uint256 poolId) external nonReentrant {
        Pool storage pl = pools[poolId];
        require(block.timestamp < pl.deadline && pl.tokenAddress == address(0), "Pool staking period has ended");

        uint256 stakeAmount = userStakes[msg.sender][poolId];
        require(stakeAmount > 0, "No stake to withdraw");
        pl.totalStaked -= stakeAmount;
        pl.totalScore -= userScores[msg.sender][poolId];
        totalStakeScore -= stakeAmount;
        userTotalStakeScore[msg.sender] -= stakeAmount;
        uint256 fee = (stakeAmount * 25) / 1000;
        uint256 amountToReturn = stakeAmount - fee;
        userScores[msg.sender][poolId] = 0;
        userStakes[msg.sender][poolId] = 0;

        (bool feeSuccess, ) = feeRecipient.call{value: fee}("");
        require(feeSuccess, "Transfer failed");
        (bool success, ) = msg.sender.call{value: amountToReturn}("");
        require(success, "Transfer failed");

        emit Unstake(msg.sender, poolId, amountToReturn);
    }

    function deployToken(uint256 poolId) external {
        require(poolId <= poolCount, "Invalid Pool");
        Pool storage pl = pools[poolId];
        require(
            block.timestamp >= pl.deadline ||
                pl.currentParticipants >= pl.maxParticipants,
            "Pool staking period has not ended or maximum participants not reached"
        );
        require(pl.tokenAddress == address(0), "Token already deployed");

        poolToken token = new poolToken(pl.name, pl.symbol, address(this));
        pl.tokenAddress = address(token);
        token.mint(address(this), pl.totalSupply * 10 ** 18);
        // airdrop
        token.transfer(airdropContract, pl.totalSupply * 10 ** 18 / 10);
        emit TokenDeployed(poolId, pl.tokenAddress);
    }

    function claim(uint256 poolId, bytes32[] calldata merkleProof) external {
        Pool storage pl = pools[poolId];
        require(pl.tokenAddress != address(0), "Token not deployed yet");

        if (pl.useWhitelist) {
            require(
                whitelistContract.verify(
                    pl.whitelistIndex,
                    msg.sender,
                    merkleProof
                ),
                "Address is not whitelisted"
            );
        }
        require(!hasClaimed[msg.sender][poolId], "Already claimed");

        uint256 userScore = userScores[msg.sender][poolId];
        require(userScore > 0, "No token to claim");
        uint256 airdropAmount = pl.totalSupply * 10 ** 18 / 10;
        
        uint256 tokenAmount = (userScores[msg.sender][poolId] * (pl.totalSupply * 10 ** 18 - airdropAmount)) / pl.totalScore;
        uint256 fee = tokenAmount/100;
        tokenAmount -= fee;

        hasClaimed[msg.sender][poolId] = true;

        poolToken(pl.tokenAddress).transfer(msg.sender, tokenAmount);
        poolToken(pl.tokenAddress).transfer(feeRecipient, fee);


        emit Claim(msg.sender, poolId, tokenAmount);
    }

    function estimateClaimableTokens(uint256 poolId, address user) external view returns (uint256) {
        Pool storage pl = pools[poolId];
        
        if (hasClaimed[user][poolId]) {
            return 0;
        }

        uint256 userScore = userScores[user][poolId];

        if (userScore == 0) {
            return 0;
        }
        uint256 tokenAmount = (userScore * (pl.totalSupply * 10 ** 18 - pl.totalSupply * 10 ** 18 / 10)) / pl.totalScore;
        tokenAmount -= tokenAmount/100;
        return tokenAmount;
    }

    function withdraw(uint256 poolId) external nonReentrant {
        Pool storage pl = pools[poolId];
        require(
            block.timestamp >= pl.deadline || pl.tokenAddress != address(0),
            "Pool staking period has not ended"
        );

        uint256 stakeAmount = userStakes[msg.sender][poolId];
        require(stakeAmount > 0, "No stake to withdraw");
        userStakes[msg.sender][poolId] = 0;
        (bool success, ) = msg.sender.call{value: stakeAmount}("");
        require(success, "Transfer failed");
        emit Unstake(msg.sender, poolId, stakeAmount);
    }
    
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
