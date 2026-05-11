const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("WaveScheduler", function () {
  let WaveScheduler;
  let waveScheduler;
  let owner;
  let addr1;
  let addr2;

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    WaveScheduler = await ethers.getContractFactory("WaveScheduler");
    waveScheduler = await WaveScheduler.deploy(owner.address);
    // await waveScheduler.deployed(); // Not needed in newer ethers
  });

  describe("Waves", function () {
    it("Should create a new wave", async function () {
      const startTime = Math.floor(Date.now() / 1000) + 60; // 1 minute from now
      const duration = 3600; // 1 hour
      const budget = ethers.parseEther("1.0");

      await expect(waveScheduler.createWave(startTime, duration, { value: budget }))
        .to.emit(waveScheduler, "WaveCreated")
        .withArgs(0, budget, startTime, duration);

      const wave = await waveScheduler.waves(0);
      expect(wave.budget).to.equal(budget);
      expect(wave.startTime).to.equal(startTime);
      expect(wave.duration).to.equal(duration);
    });

    it("Should fail if not maintainer", async function () {
      const startTime = Math.floor(Date.now() / 1000) + 60;
      await expect(
        waveScheduler.connect(addr1).createWave(startTime, 3600, { value: ethers.parseEther("1.0") })
      ).to.be.revertedWith("Caller is not a maintainer");
    });
  });

  describe("Task Claims", function () {
    let startTime, duration, waveId;

    beforeEach(async function () {
      startTime = Math.floor(Date.now() / 1000) - 60; // Started 1 minute ago
      duration = 3600;
      waveId = 0;
      await waveScheduler.createWave(startTime, duration, { value: ethers.parseEther("1.0") });
    });

    it("Should allow claiming a task", async function () {
      const taskId = ethers.id("task1");
      const secret = "my secret";
      const commitHash = ethers.solidityPackedKeccak256(["string"], [secret]);

      await expect(waveScheduler.connect(addr1).claimTask(waveId, taskId, commitHash))
        .to.emit(waveScheduler, "TaskClaimed")
        .withArgs(waveId, addr1.address, taskId, commitHash);
    });

    it("Should allow revealing a task", async function () {
      const taskId = ethers.id("task1");
      const secret = "my secret";
      const commitHash = ethers.solidityPackedKeccak256(["string"], [secret]);

      await waveScheduler.connect(addr1).claimTask(waveId, taskId, commitHash);
      
      await expect(waveScheduler.connect(addr1).revealTask(waveId, taskId, secret))
        .to.emit(waveScheduler, "TaskRevealed")
        .withArgs(waveId, addr1.address, taskId);
    });
  });
});
