// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract AscensionCatty is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2222;
    uint256 public constant MAX_PER_WALLET = 20;
    uint256 public constant FREE_PRICE = 0.0005 ether;
    uint256 public constant SUMMON_PRICE = 0.005 ether;

    uint256 public totalMinted;
    bool public mintOpen;
    string private _baseTokenURI;

    mapping(address => uint256) public mintedBy;
    mapping(uint256 => bool) public isSummoned;

    event Minted(address indexed to, uint256 fromId, uint256 qty, bool summon);

    constructor(string memory baseURI_) ERC721("Ascension Catty", "ACAT") Ownable(msg.sender) {
        _baseTokenURI = baseURI_;
    }

    function freeMint(uint256 qty) external payable nonReentrant { _mintTier(qty, FREE_PRICE, false); }
    function summonMint(uint256 qty) external payable nonReentrant { _mintTier(qty, SUMMON_PRICE, true); }

    function _mintTier(uint256 qty, uint256 price, bool summon) internal {
        require(mintOpen, "Mint closed");
        require(qty > 0, "Qty 0");
        require(totalMinted + qty <= MAX_SUPPLY, "Sold out");
        require(mintedBy[msg.sender] + qty <= MAX_PER_WALLET, "Max 20 per wallet");
        require(msg.value == price * qty, "Wrong BNB amount");
        mintedBy[msg.sender] += qty;
        uint256 startId = totalMinted + 1;
        totalMinted += qty;
        for (uint256 i = 0; i < qty; i++) {
            uint256 id = startId + i;
            if (summon) isSummoned[id] = true;
            _safeMint(msg.sender, id);
        }
        emit Minted(msg.sender, startId, qty, summon);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }
    function setBaseURI(string calldata newBase) external onlyOwner { _baseTokenURI = newBase; }

    function withdraw() external onlyOwner nonReentrant {
        (bool ok, ) = payable(owner()).call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    // required overrides
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        return super._update(to, tokenId, auth);
    }
    function _increaseBalance(address account, uint128 value) internal override {
        super._increaseBalance(account, value);
    }
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
