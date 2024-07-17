// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Whitelist is Initializable, OwnableUpgradeable, UUPSUpgradeable  {
    struct WhitelistInfo {
        bytes32 merkleRoot;
        address uploader;
    }
    function initialize(
        address _admin
    ) initializer public {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();
    }

    mapping(uint256 => WhitelistInfo) public whitelists;
    uint256 public whitelistCount;

    event WhitelistUploaded(uint256 indexed whitelistId, bytes32 merkleRoot, address uploader, string description);

    function uploadWhitelist(bytes32  _merkleRoot, address _uploader, string calldata _description) external {
        whitelistCount++;
        whitelists[whitelistCount] = WhitelistInfo({
            merkleRoot: _merkleRoot,
            uploader: _uploader
        });

        emit WhitelistUploaded(whitelistCount, _merkleRoot, _uploader, _description);
    }

    function setWhitelistMerkleRoot(uint256 whitelistId, bytes32 _whitelistMerkleRoot) external {
        require(whitelistId <= whitelistCount, "Invalid whitelistId");
        WhitelistInfo storage whitelistInfo = whitelists[whitelistId];
        require(msg.sender == whitelistInfo.uploader, "Only uploader can set whitelist root");
        require(whitelistInfo.merkleRoot == bytes32(0), "Whitelist root already set");

        whitelistInfo.merkleRoot = _whitelistMerkleRoot;

        emit WhitelistUploaded(whitelistCount, _whitelistMerkleRoot, msg.sender, "upload MerkleRoot");
    }

    function verify(uint256 whitelistId, address account, bytes32[] calldata merkleProof) external view returns (bool) {
        WhitelistInfo storage whitelistInfo = whitelists[whitelistId];
        require(whitelistInfo.merkleRoot != bytes32(0), "Whitelist root unset");
        bytes32 leaf = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(merkleProof, whitelistInfo.merkleRoot, leaf);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

