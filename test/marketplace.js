const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Marketplace", function () {
  async function deployFixture() {
    const [owner, addr1, addr2] = await ethers.getSigners();

    const provider = ethers.getDefaultProvider();

    const Marketplace = await ethers.getContractFactory("Marketplace");
    const marketplace = await Marketplace.deploy();
    await marketplace.deployed();

    const Creator = await ethers.getContractFactory("Creator");
    const creator = await Creator.deploy();
    await creator.deployed();

    await marketplace.setCreator(creator.address);
    await creator.setMarketplace(marketplace.address);

    return {
      owner,
      addr1,
      addr2,
      marketplace,
      creator,
      provider,
    };
  }

  describe("Deployment", function () {
    it("Should have the correct setting between marketplace and creator", async function () {
      const { owner, marketplace, creator, provider } = await loadFixture(
        deployFixture
      );

      expect(await marketplace.creatorContractAddress()).to.equal(
        creator.address
      );
      expect(await creator.marketplaceContractAddress()).to.equal(
        marketplace.address
      );
    });
  });

  describe("Marketplace", function () {
    it("Should be able to create a new NFT", async () => {
      const { owner, marketplace, creator, provider } = await loadFixture(
        deployFixture
      );

      // Create an NFT with 10% royalty fee
      let dummyTokenURI = "0x0";
      await marketplace.createNFT(
        dummyTokenURI,
        ethers.utils.parseUnits("0.01", "gwei")
      );

      // We have only minted 1 NFT, so the ID is 1
      let tokenId = 1;

      // Check that the NFT was created
      expect(await creator.tokenURI(tokenId)).to.equal(dummyTokenURI);
    });

    it("Should NOT be able to create a new NFT if not paying the correct creator fee", async () => {
      const { owner, marketplace, creator, provider } = await loadFixture(
        deployFixture
      );

      // set the creator fee to 0.01ETH
      let creatorFee = ethers.utils.parseUnits("0.01", "ether");
      await marketplace.setCreatorFee(creatorFee);

      // Create an NFT with 10% royalty fee
      let dummyTokenURI = "0x0";

      // Expect to fail
      await expect(
        marketplace.createNFT(
          dummyTokenURI,
          ethers.utils.parseUnits("0.01", "gwei"),
          {
            value: creatorFee.sub(1),
          }
        )
      ).to.revertedWith("creator fee not correct");
    });

    it("Should be able to create a new NFT with correct royalty settings", async () => {
      const { owner, marketplace, creator, provider } = await loadFixture(
        deployFixture
      );

      // Create an NFT with 10% royalty fee
      let dummyTokenURI = "0x0";
      let royaltyFee = ethers.utils.parseUnits("0.01", "gwei");
      await marketplace.createNFT(dummyTokenURI, royaltyFee);

      // We have only minted 1 NFT, so the ID is 1
      let tokenId = 1;

      // Check the royalty fee is correct
      let creatorRoyalties = await marketplace.creatorRoyalties(
        creator.address,
        1
      );

      expect(creatorRoyalties).to.equal(royaltyFee);

      // Check the creator address is correct
      let creatorAddress = await marketplace.creatorAddress(
        creator.address,
        tokenId
      );

      expect(creatorAddress).to.equal(owner.address);
    });

    it("Should be able to list the newly created NFT", async () => {
      const { owner, marketplace, creator, provider } = await loadFixture(
        deployFixture
      );

      // Create an NFT with 10% royalty fee
      let dummyTokenURI = "0x0";
      let royaltyFee = ethers.utils.parseUnits("0.01", "gwei");
      await marketplace.createNFT(dummyTokenURI, royaltyFee);

      // We have only minted 1 NFT, so the ID is 1
      let tokenId = 1;

      // Approve the token for the marketplace
      await creator.approve(marketplace.address, tokenId);

      // Define the price
      let price = ethers.utils.parseUnits("0.1", "ether");
      await marketplace.listItem(creator.address, tokenId, price);

      let item = await marketplace.getItem(tokenId);

      // verify information of the listed item
      expect(await item.contractAddress).to.equal(creator.address);
      expect(await item.tokenId).to.equal(tokenId);
      expect(await item.price).to.equal(price);
      expect(await item.seller).to.equal(owner.address);
      expect(await item.isListed).to.equal(true);

      // count the listed items
      expect((await marketplace.getItems(true)).length).to.equal(1);
    });

    it("Should be able to sell an NFT", async () => {
      const { owner, addr1, marketplace, creator, provider } =
        await loadFixture(deployFixture);

      // Create an NFT with 10% royalty fee
      let dummyTokenURI = "0x0";
      let royaltyFee = ethers.utils.parseUnits("0.01", "gwei");
      await marketplace.createNFT(dummyTokenURI, royaltyFee);

      // We have only minted 1 NFT, so the ID is 1
      let tokenId = 1;

      // Approve the token for the marketplace
      await creator.approve(marketplace.address, tokenId);

      // Define the price
      let price = ethers.utils.parseUnits("0.1", "ether");
      await marketplace.listItem(creator.address, tokenId, price);

      let item = await marketplace.getItem(tokenId);

      // cannot buy the item with incorrect price
      await expect(
        marketplace.connect(addr1).sale(creator.address, tokenId)
      ).to.revertedWith("invalid payment");

      // able to buy the item with correct price
      await expect(
        marketplace.connect(addr1).sale(creator.address, tokenId, {
          value: price,
        })
      )
        .to.emit(marketplace, "Sale")
        .withArgs(
          owner.address,
          addr1.address,
          creator.address,
          tokenId,
          price
        );
    });
  });
});
