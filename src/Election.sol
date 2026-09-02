// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Election
/// @notice A simple on-chain election contract: a chairman registers voters,
///         creates parties and candidates, runs the vote, and the winner is
///         computed from the tallied votes.
contract Election {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    error Election__NotChairman();
    error Election__NotStarted();
    error Election__AlreadyStarted();
    error Election__AlreadyEnded();
    error Election__CandidateDoesNotExist();
    error Election__CandidateDeleted();
    error Election__PartyDoesNotExist();
    error Election__NotRegistered();
    error Election__AlreadyRegistered();
    error Election__AlreadyVoted();
    error Election__NotOldEnough();
    error Election__NoCandidates();

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------
    struct Candidate {
        address candidateAddr;
        string candidateName;
        uint256 partyId;
        uint256 totalCandidateVote;
        bool isDeleted;
    }

    struct Party {
        string partyName;
    }

    // ---------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------
    address public chairman;
    bool public isElectionStarted;
    bool public isElectionEnded;

    Candidate[] public candidates;
    Party[] public parties;

    // candidate address => 1-based candidate id (0 means "no candidate")
    mapping(address => uint256) public candidateIdByAddress;

    // voter address => registered by chairman
    mapping(address => bool) public isRegisteredVoter;

    // voter address => already cast a vote
    mapping(address => bool) public hasVoted;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------
    event PartyCreated(uint256 indexed partyId, string name);
    event CandidateCreated(uint256 indexed candidateId, address indexed candidateAddr, string name, uint256 indexed partyId);
    event CandidateRemoved(uint256 indexed candidateId);
    event VoterRegistered(address indexed voter);
    event ElectionStarted();
    event ElectionEnded(uint256 winningCandidateId);
    event VoteCast(address indexed voter, uint256 indexed candidateId);

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------
    modifier onlyChairman() {
        if (msg.sender != chairman) revert Election__NotChairman();
        _;
    }

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------
    /// @dev The original contract never set `chairman`, so it defaulted to
    ///      address(0) and every chairman-only function was permanently
    ///      unusable. Whoever deploys the contract becomes the chairman.
    constructor() {
        chairman = msg.sender;
    }

    // ---------------------------------------------------------------------
    // Party management
    // ---------------------------------------------------------------------
    function createParties(string memory _partyName) public onlyChairman returns (uint256 partyId) {
        if (isElectionStarted) revert Election__AlreadyStarted();

        parties.push(Party({partyName: _partyName}));
        partyId = parties.length - 1;

        emit PartyCreated(partyId, _partyName);
    }

    function getPartyCount() public view returns (uint256) {
        return parties.length;
    }

    // ---------------------------------------------------------------------
    // Candidate management
    // ---------------------------------------------------------------------
    function createCandidates(address _candidateAddress, string memory _name, uint256 _partyId)
        public
        onlyChairman
        returns (uint256 candidateId)
    {
        if (isElectionStarted) revert Election__AlreadyStarted();
        if (_partyId >= parties.length) revert Election__PartyDoesNotExist();

        candidates.push(
            Candidate({
                candidateAddr: _candidateAddress,
                candidateName: _name,
                partyId: _partyId,
                totalCandidateVote: 0,
                isDeleted: false
            })
        );

        candidateId = candidates.length; // 1-based id
        candidateIdByAddress[_candidateAddress] = candidateId;

        emit CandidateCreated(candidateId, _candidateAddress, _name, _partyId);
    }

    /// @param _candidateId the 1-based id returned by createCandidates
    function removeCandidates(uint256 _candidateId) public onlyChairman {
        if (_candidateId == 0 || _candidateId > candidates.length) revert Election__CandidateDoesNotExist();

        Candidate storage c = candidates[_candidateId - 1];
        c.isDeleted = true;
        delete candidateIdByAddress[c.candidateAddr];

        emit CandidateRemoved(_candidateId);
    }

    function getCandidateCount() public view returns (uint256) {
        return candidates.length;
    }

    // ---------------------------------------------------------------------
    // Election lifecycle
    // ---------------------------------------------------------------------
    function getElectionStarted() public onlyChairman {
        if (isElectionStarted) revert Election__AlreadyStarted();
        if (candidates.length == 0) revert Election__NoCandidates();

        isElectionStarted = true;
        emit ElectionStarted();
    }

    function endElection() public onlyChairman {
        if (!isElectionStarted) revert Election__NotStarted();
        if (isElectionEnded) revert Election__AlreadyEnded();

        isElectionEnded = true;
        emit ElectionEnded(getWinner());
    }

    // ---------------------------------------------------------------------
    // Voter registration
    // ---------------------------------------------------------------------
    /// @dev Only the chairman can register voters. The original contract
    ///      required `voter == chairman`, which made it impossible for
    ///      anyone but the chairman to ever be registered.
    function registerVoters(uint16 _age, address _voter) public onlyChairman returns (bool) {
        if (_age < 18) revert Election__NotOldEnough();
        if (isRegisteredVoter[_voter]) revert Election__AlreadyRegistered();

        isRegisteredVoter[_voter] = true;
        emit VoterRegistered(_voter);
        return true;
    }

    // ---------------------------------------------------------------------
    // Voting
    // ---------------------------------------------------------------------
    /// @param _candidateId the 1-based id returned by createCandidates
    function vote(uint256 _candidateId) public {
        if (!isElectionStarted) revert Election__NotStarted();
        if (isElectionEnded) revert Election__AlreadyEnded();
        if (_candidateId == 0 || _candidateId > candidates.length) revert Election__CandidateDoesNotExist();

        Candidate storage c = candidates[_candidateId - 1];
        if (c.isDeleted) revert Election__CandidateDeleted();
        if (!isRegisteredVoter[msg.sender]) revert Election__NotRegistered();
        if (hasVoted[msg.sender]) revert Election__AlreadyVoted();

        c.totalCandidateVote += 1;
        hasVoted[msg.sender] = true;

        emit VoteCast(msg.sender, _candidateId);
    }

    // ---------------------------------------------------------------------
    // Results
    // ---------------------------------------------------------------------
    /// @return winningCandidateId the 1-based id of the candidate with the
    ///         most votes (0 if no votes have been cast yet).
    function getWinner() public view returns (uint256 winningCandidateId) {
        if (candidates.length == 0) revert Election__NoCandidates();

        uint256 highestVotes = 0;
        for (uint256 i = 0; i < candidates.length; i++) {
            if (candidates[i].isDeleted) continue;
            if (candidates[i].totalCandidateVote > highestVotes) {
                highestVotes = candidates[i].totalCandidateVote;
                winningCandidateId = i + 1;
            }
        }
    }

    function getCandidate(uint256 _candidateId)
        public
        view
        returns (address candidateAddr, string memory name, uint256 partyId, uint256 totalVotes, bool isDeleted)
    {
        if (_candidateId == 0 || _candidateId > candidates.length) revert Election__CandidateDoesNotExist();
        Candidate storage c = candidates[_candidateId - 1];
        return (c.candidateAddr, c.candidateName, c.partyId, c.totalCandidateVote, c.isDeleted);
    }
}

