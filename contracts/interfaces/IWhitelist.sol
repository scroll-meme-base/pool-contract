// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


interface IWhitelist {
    function verify(
        uint256 whitelistId,
        address account,
        bytes32[] calldata merkleProof
    ) external view returns (bool);
}