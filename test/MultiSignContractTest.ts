import  hre from "hardhat";
import { expect } from "chai";
import { loadFixture } from "ethereum-waffle";
import { defaultAbiCoder,parseEther } from "ethers/lib/utils";


const ethers = hre.ethers;
describe("MultiSignContract", () => {
  const addresses = [
    "0x6325439389E0797Ab35752B4F43a14C004f22A9c",
    "0xfe8c1ac365ba6780aec5a985d989b327c27670a1",
    "0x990eB28e378659b93A29D46fF41F08DC6316DD98",
    "0xEBba467eCB6b21239178033189CeAE27CA12EaDf",
  ];
  const prices = [
    parseEther("0.415"),
    parseEther("0.8"),
    parseEther("0.5"),
    parseEther("0.15"),
  ];

  const deployContract = async () => {
    const [admin, Alice, Bob, Cindy, Daniel] = await ethers.getSigners();
    const requiredConfirmations = 2;
    const PriceOracle = await ethers.getContractFactory("PriceOracle");
    const priceOracle = await PriceOracle.deploy();
    await priceOracle.deployed();

    const priceOracleAddress = priceOracle.address;
    const signers = [Alice.address, Bob.address, Cindy.address];
    const MultiSignContract = await ethers.getContractFactory(
      "MultiSignContract"
    );
    const multiSignContract = await MultiSignContract.deploy(
      signers,
      requiredConfirmations,
      admin.address,
      priceOracleAddress
    );
    await multiSignContract.deployed();
    return {
      multiSignContract,
      signers,
      admin,
      requiredConfirmations,
      priceOracleAddress,
      Alice,
      Bob,
      Cindy,
      Daniel,
    };
  };

  const deployLockFixture = async () => {
    const {
      multiSignContract,
      signers,
      admin,
      requiredConfirmations,
      priceOracleAddress,
      Alice,
      Bob,
      Cindy,
      Daniel,
    } = await deployContract();
    return {
      multiSignContract,
      signers,
      admin,
      requiredConfirmations,
      priceOracleAddress,
      Alice,
      Bob,
      Cindy,
      Daniel,
    };
  };

  describe("deployment", async () => {
    it("Should set correct initial values", async () => {
      const {
        multiSignContract,
        signers,
        admin,
        requiredConfirmations,
        priceOracleAddress,
      } = await loadFixture(deployLockFixture);
      expect(await multiSignContract.requiredConfirmations()).to.equal(
        requiredConfirmations
      );
      expect(await multiSignContract.admin()).to.equal(admin.address);
      expect(await multiSignContract.priceOracleAddress()).to.equal(
        priceOracleAddress
      );
      expect(await multiSignContract.currentRound()).to.equal(0);
      expect(await multiSignContract.getSigners()).to.eql(signers);
    });
  });

  describe("signer", async () => {
    it("Should remove signer failed with not a signer", async () => {
      const { multiSignContract, Daniel } = await loadFixture(
        deployLockFixture
      );
      expect(await multiSignContract.isSigner(Daniel.address)).to.be.false;
      await expect(
        multiSignContract.removeSigner(Daniel.address)
      ).to.be.revertedWith("Not signer");
    });

    it("Should add new signer failed with is already a signer", async () => {
      const { multiSignContract, Cindy } = await loadFixture(deployLockFixture);
      expect(await multiSignContract.isSigner(Cindy.address)).to.be.true;
      await expect(
        multiSignContract.addSigner(Cindy.address)
      ).to.be.revertedWith("Signer already exists");
    });

    it("Should remove signer successfully", async function () {
      const { multiSignContract, Cindy } = await loadFixture(deployLockFixture);
      await multiSignContract.removeSigner(Cindy.address);
      expect(await multiSignContract.isSigner(Cindy.address)).to.be.false;
    });

    it("Should remove signer failed with not enough signers", async () => {
      const { multiSignContract, Bob } = await loadFixture(deployLockFixture);
      const signer = await multiSignContract.getSigners();
      expect(
        Number(await multiSignContract.requiredConfirmations()) ===
          signer.length
      ).to.be.true;
      await expect(
        multiSignContract.removeSigner(Bob.address)
      ).to.be.revertedWith("Not enough signers");
    });

    it("Should add new signer successfully", async () => {
      const { multiSignContract, Daniel } = await loadFixture(
        deployLockFixture
      );
      await multiSignContract.addSigner(Daniel.address);
      expect(await multiSignContract.isSigner(Daniel.address)).to.be.true;
    });
  });

  describe("update price", async () => {
    const addConfirmInfoFixture = async () => {
      const initiateData = defaultAbiCoder.encode(
        ["address[]", "uint256[]"],
        [addresses, prices]
      );
      const {
        multiSignContract,
        requiredConfirmations,
        Alice,
        Bob,
        Cindy,
        Daniel,
      } = await deployContract();
      return {
        multiSignContract,
        requiredConfirmations,
        Alice,
        Bob,
        Cindy,
        Daniel,
        initiateData,
      };
    };

    it("Should initiate an update price request successfully", async () => {
      const { multiSignContract, initiateData } = await loadFixture(
        addConfirmInfoFixture
      );
      const tx = await multiSignContract.initiateAnUpdatePrice(initiateData);
      const receipt = await tx.wait();
      const roundId = receipt.events![0].args!.roundId;
      const data = receipt.events![0].args!.data;
      const confirmInfo = await multiSignContract.confirmInfos(roundId);
      expect(confirmInfo.startTimestamp).to.be.gt(0);
      expect(data).equal(initiateData);
    });

    it("Should confirm an update price request failed with not a signer", async () => {
      const { multiSignContract, Daniel } = await loadFixture(
        addConfirmInfoFixture
      );
      const roundId = Number(await multiSignContract.currentRound());
      await expect(
        multiSignContract.connect(Daniel).signerConfirms(roundId)
      ).to.be.revertedWith("Not signer");
    });

    it("Should confirm an update price request by signer successfully", async () => {
      const { multiSignContract, Bob } = await loadFixture(
        addConfirmInfoFixture
      );
      const roundId = Number(await multiSignContract.currentRound());
      await multiSignContract.connect(Bob).signerConfirms(roundId);
      const confirmInfo = await multiSignContract.confirmInfos(roundId);
      expect(await multiSignContract.checkIsConfirmed(roundId, Bob.address)).to
        .be.true;
      expect(Number(confirmInfo.numConfirmations)).equal(1);
    });
    it("Should confirm an update price request failed with already confirmed", async () => {
      const { multiSignContract, Bob } = await loadFixture(
        addConfirmInfoFixture
      );
      const roundId = Number(await multiSignContract.currentRound());
      await expect(
        multiSignContract.connect(Bob).signerConfirms(roundId)
      ).to.be.revertedWith("Already confirmed");
    });

    it("Should execute an update price request failed with not enough confirmations", async () => {
      const { multiSignContract } = await loadFixture(addConfirmInfoFixture);
      const roundId = Number(await multiSignContract.currentRound());
      await expect(
        multiSignContract.executeUpdatePrice(roundId, addresses, prices)
      ).to.be.revertedWith("Not enough confirmations");
    });

    it("Should execute an update price request successfully", async function () {
      const { multiSignContract, Cindy } = await loadFixture(
        addConfirmInfoFixture
      );
      const roundId = Number(await multiSignContract.currentRound());
      await multiSignContract.connect(Cindy).signerConfirms(roundId);
      await multiSignContract.executeUpdatePrice(roundId, addresses, prices);
      const confirmInfo = await multiSignContract.confirmInfos(roundId);
      expect(confirmInfo.executed).to.be.true;
      expect(confirmInfo.endTimestamp).to.gt(0);
    });

    it("Should execute an update price request failed with already executed", async () => {
      const { multiSignContract } = await loadFixture(
        addConfirmInfoFixture
      );
      const roundId = Number(await multiSignContract.currentRound());
      await expect(
        multiSignContract.executeUpdatePrice(roundId, addresses, prices)
      ).to.be.revertedWith("confirmInfo already executed");
    });
  });

  describe("onlyAdmin function", async () => {
    it("should revert when non-admin tries to call functions with onlyAdmin modifier", async () => {
      const { multiSignContract, Alice, Bob } = await loadFixture(
        deployLockFixture
      );
      expect(multiSignContract.admin()).not.equal(Alice.address);

      await expect(
        multiSignContract.connect(Alice).setRequiredConfirmations(1)
      ).to.be.revertedWith("Not admin");

      await expect(
        multiSignContract.connect(Alice).setAdmin(Bob.address)
      ).to.be.revertedWith("Not admin");

      await expect(
        multiSignContract
          .connect(Alice)
          .setPriceOracleAddress(ethers.Wallet.createRandom().address)
      ).to.be.revertedWith("Not admin");

      await expect(
        multiSignContract.connect(Alice).removeSigner(Bob.address)
      ).to.be.revertedWith("Not admin");
    });

    it("should allow admin to call functions with onlyAdmin modifier", async () => {
      const { multiSignContract, Bob, Alice } = await loadFixture(
        deployLockFixture
      );
      await expect(multiSignContract.setRequiredConfirmations(1)).to.not.be
        .reverted;

      await expect(
        multiSignContract.setPriceOracleAddress(
          ethers.Wallet.createRandom().address
        )
      ).to.not.be.reverted;

      await expect(multiSignContract.removeSigner(Alice.address)).to.not.be
        .reverted;

      await expect(multiSignContract.setAdmin(Bob.address)).to.not.be.reverted;
    });
  });
});
