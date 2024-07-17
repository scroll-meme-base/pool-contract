// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ITokenpool.sol";



contract VoteContract is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    struct Proposal {
        string name;
        string symbol;
        uint256 duration;
        uint256 totalSupply;
        uint256 votes;
        uint256 maxParticipants;
        uint256 miniStakeValue;
        uint256 maxStakeValue;
        uint256 whitelistIndex;
        bool useWhitelist;
        bool executed;
    }

    struct ProposalParams {
        uint256 topicId;
        string name;
        string symbol;
        uint256 maxParticipants;
        uint256 duration;
        uint256 totalSupply;
        uint256 miniStakeValue;
        uint256 maxStakeValue;
        uint256 whitelistIndex;
        bool useWhitelist;
    }

    struct ProposalCreatedParams {
        uint256 topicId;
        uint256 proposalId;
        string name;
        string symbol;
        uint256 duration;
        uint256 totalSupply;
        uint256 miniStakeValue;
        uint256 maxStakeValue;
        uint256 maxParticipants;
        uint256 whitelistIndex;
        address proposer;
        bool useWhitelist;
    }


    struct Topic {
        uint256 deadline;
        uint256 highestVotes;
        bool active;
    }

    
    ITokenpool public tokenpool;
    address public  topicAdmin;
    uint256 public proposalCount;
    uint256 public topicCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Topic) public topics;
    mapping(address => mapping(uint256 => bool)) public hasVoted;
    mapping(uint256 => uint256[]) public topicProposals;
    mapping(uint256 => uint256) public proposalToTopic;
    uint256 public constant EARLY_EXECUTE_THRESHOLD = 510;

    event TopicStarted(uint256 topicId, string name, uint256 deadline);
    event ProposalCreated(ProposalCreatedParams params);
    event VoteCast(address voter, uint256 proposalId);
    event ProposalExecuted(uint256 topicId,uint256 proposalId,uint256 poolId);

    function initialize(
        address _admin,
        address _topicAdmin
    ) initializer public {
        __Ownable_init(_admin);
        __UUPSUpgradeable_init();
        topicAdmin = _topicAdmin;
    }

    modifier onlyTopicAdmin() {
        require(
            msg.sender == topicAdmin || topicAdmin == address(0),
            "Only the topicAdmin can call"
        );
        _;
    }

    modifier validProposal(uint256 proposalId) {
        require(proposalId <= proposalCount, "Invalid proposal");
        _;
    }

    modifier validTopic(uint256 topicId) {
        require(topicId <= topicCount, "Invalid topic");
        _;
    }

    function transferTopicAdmin(address _newTopicAdmin) external  onlyTopicAdmin {
        require(topicAdmin != address(0),"TransferTopicAdmin is disabled");
        topicAdmin = _newTopicAdmin;
    }


    function setTokenpool(address _tokenpool) external onlyOwner {
        require(address(tokenpool) == address(0), "Tokenpool already set");
        tokenpool = ITokenpool(_tokenpool);
    }

    function startTopic(string calldata name,uint256 duration) external onlyTopicAdmin {
        topicCount++;
        uint256 deadline = block.timestamp + duration;
        topics[topicCount] = Topic({
            deadline: deadline,
            highestVotes: 0,
            active: true
        });

        emit TopicStarted(topicCount, name, deadline);
    }

    function createProposal(
        ProposalParams calldata params
    ) external validTopic(params.topicId)  {
        require(block.timestamp < topics[params.topicId].deadline, "Topic deadline has passed");
        require(bytes(params.name).length > 0, "Name cannot be empty");
        require(bytes(params.symbol).length > 0, "Symbol cannot be empty");
        require(params.duration > 0, "Duration must be greater than 0");
        require(params.totalSupply > 0, "Total supply must be greater than 0");
        require(params.maxParticipants > 0, "Max participants must be greater than 0");
        require(
            params.miniStakeValue > 0,
            "Minimum stake value must be greater than 0"
        );
        require(
            params.maxStakeValue > 0 && params.maxStakeValue >= params.miniStakeValue,
            "Maximum stake value must be greater than 0"
        );

        proposalCount++;
        proposals[proposalCount] = Proposal({
            name: params.name,
            symbol: params.symbol,
            duration: params.duration,
            totalSupply: params.totalSupply,
            useWhitelist: params.useWhitelist,
            miniStakeValue: params.miniStakeValue,
            maxStakeValue: params.maxStakeValue,
            whitelistIndex: params.whitelistIndex,
            maxParticipants: params.maxParticipants,
            votes: 0,
            executed: false
        });

        topicProposals[params.topicId].push(proposalCount);
        proposalToTopic[proposalCount] = params.topicId;
        ProposalCreatedParams memory eventParams = ProposalCreatedParams({
        topicId: params.topicId,
        proposalId: proposalCount,
        name: params.name,
        symbol: params.symbol,
        duration: params.duration,
        totalSupply: params.totalSupply,
        useWhitelist: params.useWhitelist,
        miniStakeValue: params.miniStakeValue,
        maxStakeValue: params.maxStakeValue,
        maxParticipants: params.maxParticipants,
        whitelistIndex: params.whitelistIndex,
        proposer: msg.sender
    });

        emit ProposalCreated(eventParams);
    }

    function vote(uint256 proposalId) external validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        uint256 topicId = proposalToTopic[proposalId];
        require(block.timestamp < topics[topicId].deadline, "Topic deadline has passed");
        require(!hasVoted[msg.sender][proposalId], "Already voted");

        proposal.votes++;
        hasVoted[msg.sender][proposalId] = true;

        if (topics[topicId].highestVotes == 0 || proposal.votes > topics[topicId].highestVotes) {
            topics[topicId].highestVotes = proposal.votes ;
        }

        emit VoteCast(msg.sender, proposalId);

    }

    function executeProposal(uint256 proposalId) public validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        uint256 topicId = proposalToTopic[proposalId];
        require(proposal.votes == topics[topicId].highestVotes, "Not the highest voted proposal");
        require(block.timestamp >= topics[topicId].deadline || proposal.votes >= EARLY_EXECUTE_THRESHOLD, "Topic deadline not reached or insufficient votes");
        require(!proposal.executed, "Proposal already executed");
        require(topics[topicId].active,"Topic is no active");


        proposal.executed = true;
        topics[topicId].active = false;
        tokenpool.createPool(
            proposal.name,
            proposal.symbol,
            proposal.duration,
            proposal.totalSupply,
            proposal.maxParticipants,
            proposal.miniStakeValue,
            proposal.maxStakeValue,
            proposal.whitelistIndex,
            proposal.useWhitelist
        );

        emit ProposalExecuted(topicId,proposalId,tokenpool.poolCount());
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

