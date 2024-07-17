// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


interface ITokenpool {
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
    ) external;

    function poolCount() external view returns (uint256);
    
}