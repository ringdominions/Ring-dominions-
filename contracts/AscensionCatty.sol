// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title New NFT Collection
/// @notice Single-mint ERC-721 collection with a fixed supply of 1,111.
contract AscensionCatty is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 1111;
    uint256 public constant MAX_PER_WALLET = 10;
    uint256 public constant MINT_PRICE = 0.0005 ether;

    uint256 public totalMinted;
    bool public mintOpen;
    string private baseTokenURI;
    mapping(address => uint256) public mintedBy;

    event Minted(address indexed to, uint256 quantity, uint256 firstTokenId);
    event MintStatusChanged(bool open);
    event BaseURIChanged(string newBaseURI);

    constructor(string memory initialBaseURI)
        ERC721("New NFT", "NNFT")
        Ownable(msg.sender)
    {
        baseTokenURI = initialBaseURI;
    }

    /// @notice Mint one or more NFTs. The only public mint entry point.
    function mint(uint256 quantity) external payable nonReentrant {
        require(mintOpen, "Mint is closed");
        require(quantity > 0, "Quantity is zero");
        require(totalMinted + quantity <= MAX_SUPPLY, "Sold out");
        require(mintedBy[msg.sender] + quantity <= MAX_PER_WALLET, "Wallet limit exceeded");
        require(msg.value == MINT_PRICE * quantity, "Incorrect payment");

        uint256 firstTokenId = totalMinted + 1;
        mintedBy[msg.sender] += quantity;
        totalMinted += quantity;

        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(msg.sender, firstTokenId + i);
        }

        emit Minted(msg.sender, quantity, firstTokenId);
    }

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintStatusChanged(open);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseTokenURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(baseTokenURI, tokenId.toString(), ".json");
    }
}
