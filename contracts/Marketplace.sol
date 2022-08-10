// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./Creator.sol";

contract Marketplace {
    address public owner;
    uint256 public lastItemIndex; // Should start with 1 to prevent indexOfItem from returning 0
    uint256 public transactionFee; // percentage in gwei

    bytes4 public constant ERC721InterfaceId = 0x80ac58cd;

    struct NFT {
        address contractAddress;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool isListed;
        // Only for those NFTs created by the marketplace
        uint256 royalty; // percentage in gwei
        address royaltyAddress; // the creator of the NFT
    }

    // lastItemIndex as the key, NFT as the value
    mapping(uint256 => NFT) public items;

    // address: contract address, uint256: tokenId, value: the index of the item in the items mapping
    mapping(address => mapping(uint256 => uint256)) public indexOfItem;

    // save the royalty that created with this marketplace contract, percentage in gwei
    mapping(address => mapping(uint256 => uint256)) public creatorRoyalties;

    // save the creator address that created with this marketplace contract
    mapping(address => mapping(uint256 => address)) public creatorAddress;

    // The creator address (Marketplace NFT creator)
    address public creatorContractAddress;

    // creator fee
    uint256 public creatorFee;

    // Event
    event Sale(
        address seller,
        address buyer,
        address contractAddress,
        uint256 indexed tokenId,
        uint256 indexed price
    );

    constructor() {
        owner = msg.sender;
    }

    // set creator contract address
    function setCreator(address _creator) external onlyOwner {
        creatorContractAddress = _creator;
    }

    // set creator fee
    function setCreatorFee(uint256 _fee) external onlyOwner {
        creatorFee = _fee;
    }

    // set transaction fee
    function setTransactionFee(uint256 _fee) external onlyOwner {
        transactionFee = _fee;
    }

    // Get a single item
    function getItem(uint256 key) external view returns (NFT memory) {
        return items[key];
    }

    // Get all items
    function getItems(bool isListed) external view returns (NFT[] memory) {
        NFT[] memory itemsArray = new NFT[](lastItemIndex);
        for (uint256 i = 1; i < lastItemIndex; i++) {
            if (isListed) {
                if (items[i].isListed) {
                    itemsArray[i] = items[i];
                }
            } else {
                itemsArray[i] = items[i];
            }
        }
        return itemsArray;
    }

    // List Item
    function listItem(
        address _contractAddress,
        uint256 _tokenId,
        uint256 _price
    ) external {
        // Cannot be zero address
        require(_contractAddress != address(0), "invalid contract address");

        // The listed item must be an ERC721 token
        require(
            _isERC721(_contractAddress),
            "contract address is not ERC721 compatible"
        );

        // The seller must be the owner of the token
        require(
            IERC721(_contractAddress).ownerOf(_tokenId) == msg.sender,
            "you are not the owner of this token"
        );

        // The item must be approved to this marketplace contract
        require(
            IERC721(_contractAddress).getApproved(_tokenId) == address(this),
            "token is not approved for sale"
        );

        // The item must not be listed already
        require(
            !_isListed(_contractAddress, _tokenId),
            "token is already listed"
        );

        // price cannot be 0
        require(_price > 0, "price cannot be 0");

        uint256 itemIndex;

        // Item already listed in the past, reuse that index
        if (indexOfItem[_contractAddress][_tokenId] > 0) {
            itemIndex = indexOfItem[_contractAddress][_tokenId];
        } else {
            // Increment first
            lastItemIndex++;
            itemIndex = lastItemIndex;
        }

        // Get the royalty setting
        uint256 _royalty = creatorRoyalties[_contractAddress][_tokenId];

        // Get the creator address
        address _creator = creatorAddress[_contractAddress][_tokenId];

        // List item
        items[itemIndex] = NFT(
            _contractAddress,
            _tokenId,
            msg.sender,
            _price,
            true,
            _royalty,
            _creator
        );

        // Set the index of the item in the items mapping
        indexOfItem[_contractAddress][_tokenId] = itemIndex;
    }

    // Unlist Item
    function unlistItem(address _contractAddress, uint256 _tokenId) external {
        // Cannot be zero address
        require(_contractAddress != address(0), "invalid contract address");

        // The item must be listed
        require(_isListed(_contractAddress, _tokenId), "token is not listed");

        // The seller must be the owner of the token
        require(
            IERC721(_contractAddress).ownerOf(_tokenId) == msg.sender,
            "you are not the owner of this token"
        );

        // The item must be approved to this marketplace contract
        require(
            IERC721(_contractAddress).getApproved(_tokenId) == address(this),
            "token is not approved for sale"
        );

        // Unlist item
        items[indexOfItem[_contractAddress][_tokenId]].isListed = false;
    }

    // Update price of an item
    function updatePrice(
        address _contractAddress,
        uint256 _tokenId,
        uint256 _price
    ) external {
        // Cannot be zero address
        require(_contractAddress != address(0), "invalid contract address");

        // The item must be listed
        require(_isListed(_contractAddress, _tokenId), "token is not listed");

        // The seller must be the owner of the token
        require(
            IERC721(_contractAddress).ownerOf(_tokenId) == msg.sender,
            "you are not the owner of this token"
        );

        // The item must be approved to this marketplace contract
        require(
            IERC721(_contractAddress).getApproved(_tokenId) == address(this),
            "token is not approved for sale"
        );

        // price cannot be 0
        require(_price > 0, "price cannot be 0");

        // Update price
        items[indexOfItem[_contractAddress][_tokenId]].price = _price;
    }

    // Item sale
    function sale(address _contractAddress, uint256 _tokenId) external payable {
        // Cannot be zero address
        require(_contractAddress != address(0), "invalid contract address");

        // The item must be listed
        require(_isListed(_contractAddress, _tokenId), "token is not listed");

        // The seller must be the owner of the token
        require(
            IERC721(_contractAddress).ownerOf(_tokenId) ==
                items[indexOfItem[_contractAddress][_tokenId]].seller,
            "token owner is not the seller"
        );

        // The item must be approved to this marketplace contract
        require(
            IERC721(_contractAddress).getApproved(_tokenId) == address(this),
            "token is not approved for sale"
        );

        // The payment should be correct
        require(
            msg.value == items[indexOfItem[_contractAddress][_tokenId]].price,
            "invalid payment"
        );

        // define as storage because we will update it
        NFT storage item = items[indexOfItem[_contractAddress][_tokenId]];

        address seller = item.seller;

        // Calculate the transaction fee
        uint256 transactionFeeToReceive = (item.price * transactionFee) /
            1 gwei;

        require(
            transactionFeeToReceive < item.price,
            "incorrect transaction fee"
        );

        uint256 royaltyToPay = 0;

        // Check if this item has royalties
        if (items[indexOfItem[_contractAddress][_tokenId]].royalty > 0) {
            royaltyToPay = (item.price * item.royalty) / 1 gwei; // royalty set in gwei

            require(royaltyToPay < item.price, "incorrect setting for royalty");
            require(
                royaltyToPay + transactionFeeToReceive < item.price,
                "royalty and transaction fee too high"
            );

            // Transfer the royalty to the NFT creator
            payable(item.royaltyAddress).transfer(royaltyToPay);
        }

        uint256 amountToSeller = item.price -
            royaltyToPay -
            transactionFeeToReceive;

        // Pay to the seller
        payable(seller).transfer(amountToSeller);

        // Transfer token to the seller
        IERC721(_contractAddress).safeTransferFrom(
            seller,
            msg.sender,
            _tokenId
        );

        // Update the item setting
        item.seller = msg.sender; // Update the seller to the new owner
        item.isListed = false; // And delist it

        emit Sale(seller, msg.sender, _contractAddress, _tokenId, item.price);
    }

    // Check if an item is listed
    function _isListed(address _contractAddress, uint256 _tokenId)
        private
        view
        returns (bool)
    {
        return items[indexOfItem[_contractAddress][_tokenId]].isListed;
    }

    // Create NFT via Creator
    function createNFT(string calldata _tokenURI, uint256 _royalty)
        external
        payable
        returns (uint256)
    {
        require(
            creatorContractAddress != address(0),
            "creator contract address not setup"
        );

        if (creatorFee > 0) {
            require(creatorFee == msg.value, "creator fee not correct");
        }

        // Create the NFT
        uint256 _tokenId = Creator(creatorContractAddress).createNFT(
            msg.sender,
            _tokenURI
        );

        // Set the royalty
        creatorRoyalties[creatorContractAddress][_tokenId] = _royalty;
        creatorAddress[creatorContractAddress][_tokenId] = msg.sender;

        return _tokenId;
    }

    // Check if it is an ERC721 contract
    function _isERC721(address _contractAddress) private view returns (bool) {
        return IERC721(_contractAddress).supportsInterface(ERC721InterfaceId);
    }

    // onlyOwner modifier
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
