// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ITokenpool.sol";


contract BonusContract is Initializable, OwnableUpgradeable, UUPSUpgradeable  {
    address public tokenpool;
    address public feeRecipient;
    mapping(address => mapping(address => bool)) public hasClaimed; // user => token => claimed
    mapping(address => uint256) public airdropAmounts;

    event TokensDistributed(address indexed recipient, address indexed token, uint256 amount);


    function initialize(
        address _admin,
        address _feeRecipient
    ) initializer public {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();
        feeRecipient = _feeRecipient;
    }

    function setTokenpool(address _tokenpool) external {
        require(tokenpool == address(0), "Tokenpool already set");
        tokenpool = _tokenpool;
    }

    function distributeTokens(address tokenAddress) external  {
        require(!hasClaimed[msg.sender][tokenAddress], "Tokens already claimed");
        

        ITokenpool pool = ITokenpool(tokenpool);
        uint256 totalStakeScore = pool.totalStakeScore();
        uint256 userStakeScore = pool.userTotalStakeScore(msg.sender);

        require(totalStakeScore > 0, "Total stake score must be greater than zero");
        require(userStakeScore > 0, "User has no stake score");

        IERC20 token = IERC20(tokenAddress);
        if (airdropAmounts[tokenAddress] == 0){
            airdropAmounts[tokenAddress] = token.balanceOf(address(this));
        }
        uint256 amount = (userStakeScore * airdropAmounts[tokenAddress]) / totalStakeScore;
        if (amount > token.balanceOf(address(this))){
            amount = token.balanceOf(address(this));
        }
        require(amount > 0, "No tokens to distribute");
        

        uint256 fee = amount/100;
        amount -= fee;
        hasClaimed[msg.sender][tokenAddress] = true;
        token.transfer(msg.sender, amount);
        token.transfer(feeRecipient, fee);
        emit TokensDistributed(msg.sender, tokenAddress, amount);

    }
    
    function estimateClaimableTokens(address tokenAddress, address user) external view returns (uint256) {
        if (hasClaimed[user][tokenAddress]) {
            return 0;
        }

        ITokenpool pool = ITokenpool(tokenpool);
        uint256 totalStakeScore = pool.totalStakeScore();
        uint256 userStakeScore = pool.userTotalStakeScore(user);

        if (totalStakeScore == 0 || userStakeScore == 0) {
            return 0;
        }

        IERC20 token = IERC20(tokenAddress);
        uint256 availableAirdropAmount = airdropAmounts[tokenAddress];
        if (availableAirdropAmount == 0) {
            availableAirdropAmount = token.balanceOf(address(this));
        }
        uint256 amount = (userStakeScore * availableAirdropAmount) / totalStakeScore;
        if (amount > token.balanceOf(address(this))){
            amount = token.balanceOf(address(this));
        }
        if (amount == 0) {
            return 0;
        }

        uint256 fee = amount / 100;
        uint256 claimableAmount = amount - fee;

        return claimableAmount;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}