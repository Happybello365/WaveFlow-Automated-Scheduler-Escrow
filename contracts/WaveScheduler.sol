// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title WaveScheduler
 * @dev Manages monthly reward "Waves" with a commit-reveal scheme for task claims.
 */
contract WaveScheduler is ReentrancyGuard, AccessControl {
    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    struct Wave {
        uint256 budget;
        uint256 startTime;
        uint256 duration;
        bool distributed;
        uint256 totalAllocated;
    }

    struct Commit {
        bytes32 commitHash;
        uint256 timestamp;
        bool revealed;
    }

    mapping(uint256 => Wave) public waves;
    uint256 public waveCount;

    // Mapping of waveId => contributor => taskId => Commit
    mapping(uint256 => mapping(address => mapping(bytes32 => Commit))) public commits;

    event WaveCreated(uint256 indexed waveId, uint256 budget, uint256 startTime, uint256 duration);
    event TaskClaimed(uint256 indexed waveId, address indexed contributor, bytes32 indexed taskId, bytes32 commitHash);
    event TaskRevealed(uint256 indexed waveId, address indexed contributor, bytes32 indexed taskId);
    event RewardsDistributed(uint256 indexed waveId, uint256 totalAmount);

    constructor(address _initialAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(MAINTAINER_ROLE, _initialAdmin);
    }

    modifier onlyMaintainer() {
        require(hasRole(MAINTAINER_ROLE, msg.sender), "Caller is not a maintainer");
        _;
    }

    modifier onlyDuringWave(uint256 _waveId) {
        require(block.timestamp >= waves[_waveId].startTime, "Not started");
        require(block.timestamp <= waves[_waveId].startTime + waves[_waveId].duration, "Wave ended");
        _;
    }

    /**
     * @dev Creates a new wave and deposits budget.
     * @param _startTime The timestamp when the wave starts.
     * @param _duration The duration of the wave in seconds.
     */
    function createWave(uint256 _startTime, uint256 _duration) external payable onlyMaintainer {
        require(msg.value > 0, "Budget must be > 0");
        
        uint256 waveId = waveCount++;
        waves[waveId] = Wave({
            budget: msg.value,
            startTime: _startTime,
            duration: _duration,
            distributed: false,
            totalAllocated: 0
        });

        emit WaveCreated(waveId, msg.value, _startTime, _duration);
    }

    /**
     * @dev Claims a task by committing a hash of a secret.
     * @param _waveId The ID of the wave.
     * @param _taskId The unique identifier for the task.
     * @param _commitHash keccak256 hash of the secret.
     */
    function claimTask(uint256 _waveId, bytes32 _taskId, bytes32 _commitHash) external onlyDuringWave(_waveId) {
        require(commits[_waveId][msg.sender][_taskId].commitHash == 0, "Already committed");
        
        commits[_waveId][msg.sender][_taskId] = Commit({
            commitHash: _commitHash,
            timestamp: block.timestamp,
            revealed: false
        });

        emit TaskClaimed(_waveId, msg.sender, _taskId, _commitHash);
    }

    /**
     * @dev Reveals a task claim by providing the secret.
     * @param _waveId The ID of the wave.
     * @param _taskId The unique identifier for the task.
     * @param _secret The secret that was hashed for the commit.
     */
    function revealTask(uint256 _waveId, bytes32 _taskId, string calldata _secret) external onlyDuringWave(_waveId) {
        Commit storage commit = commits[_waveId][msg.sender][_taskId];
        require(commit.commitHash != 0, "No commit found");
        require(!commit.revealed, "Already revealed");
        
        require(keccak256(abi.encodePacked(_secret)) == commit.commitHash, "Invalid secret");
        
        commit.revealed = true;
        emit TaskRevealed(_waveId, msg.sender, _taskId);
    }

    /**
     * @dev Distributes rewards for a wave after it has ended.
     * @param _waveId The ID of the wave.
     * @param contributors List of contributor addresses.
     * @param amounts List of reward amounts corresponding to contributors.
     */
    function distributeRewards(uint256 _waveId, address[] calldata contributors, uint256[] calldata amounts) 
        external 
        onlyMaintainer 
        nonReentrant 
    {
        Wave storage wave = waves[_waveId];
        require(!wave.distributed, "Already distributed");
        require(block.timestamp > wave.startTime + wave.duration, "Wave still active");
        require(contributors.length == amounts.length, "Mismatched arrays");

        uint256 totalToDistribute = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalToDistribute += amounts[i];
        }
        require(totalToDistribute <= wave.budget, "Insufficient budget");

        wave.distributed = true;
        wave.totalAllocated = totalToDistribute;

        for (uint256 i = 0; i < contributors.length; i++) {
            (bool success, ) = contributors[i].call{value: amounts[i]}("");
            require(success, "Transfer failed");
        }

        emit RewardsDistributed(_waveId, totalToDistribute);
    }

    /**
     * @dev Withdraws unallocated funds from a distributed wave.
     * @param _waveId The ID of the wave.
     */
    function withdrawRemaining(uint256 _waveId) external onlyMaintainer {
        Wave storage wave = waves[_waveId];
        require(wave.distributed, "Not distributed yet");
        uint256 remaining = wave.budget - wave.totalAllocated;
        require(remaining > 0, "No funds left");
        
        wave.budget = wave.totalAllocated; // Mark as withdrawn
        (bool success, ) = msg.sender.call{value: remaining}("");
        require(success, "Transfer failed");
    }
}
