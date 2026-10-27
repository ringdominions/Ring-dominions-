// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @title Ascension Catty — Agent-only mint
/// @notice Only Binance Agentic Wallets holding a SPACE ID Agent ID may mint.
///         Contracts are rejected. Max 10 per Agent wallet. Unaudited.
contract AscensionCattyAgent is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2222;

    /// SPACE ID Agent ID (claimed in Binance Agentic Wallet) on BNB Chain
    IERC721 public agentId;
    uint256 public price = 0.0005 ether;
    uint256 public maxPerAgent = 10;
    uint256 public totalMinted;
    bool public mintOpen;
    string private _baseTokenURI;

    mapping(address => uint256) public mintedBy;

    event Minted(address indexed agent, uint256 fromId, uint256 qty);

    constructor(string memory baseURI_, address agentId_) ERC721("Ascension Catty", "ACAT") Ownable(msg.sender) {
        require(agentId_ != address(0), "AgentID 0");
        _baseTokenURI = baseURI_;
        agentId = IERC721(agentId_);
    }

    /// @notice Mint one cat. Send exactly currentPrice().
    function mint() external payable nonReentrant { _agentMint(1); }

    /// @notice Mint `qty` cats (max 10 per Agent wallet). Send currentPrice() * qty.
    function mint(uint256 qty) external payable nonReentrant { _agentMint(qty); }

    function currentPrice() external view returns (uint256) { return price; }

    function isAgent(address wallet) public view returns (bool) {
        return wallet.code.length == 0 && agentId.balanceOf(wallet) > 0;
    }

    function remainingFor(address wallet) external view returns (uint256) {
        uint256 used = mintedBy[wallet];
        return used >= maxPerAgent ? 0 : maxPerAgent - used;
    }

    function _agentMint(uint256 qty) internal {
        require(mintOpen, "Mint closed");
        require(msg.sender == tx.origin && msg.sender.code.length == 0, "No contracts");
        require(agentId.balanceOf(msg.sender) > 0, "Agent ID required");
        require(qty > 0, "Qty 0");
        require(totalMinted + qty <= MAX_SUPPLY, "Sold out");
        require(mintedBy[msg.sender] + qty <= maxPerAgent, "Max per Agent reached");
        require(msg.value == price * qty, "Wrong BNB amount");
        mintedBy[msg.sender] += qty;
        uint256 startId = totalMinted + 1;
        totalMinted += qty;
        for (uint256 i = 0; i < qty; i++) {
            _safeMint(msg.sender, startId + i);
        }
        emit Minted(msg.sender, startId, qty);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(_baseTokenURI, tokenId.toString(), ".json"));
    }

    // ---- owner ----
    function setMintOpen(bool open) external onlyOwner { mintOpen = open; }
    function setBaseURI(string calldata newBase) external onlyOwner { _baseTokenURI = newBase; }
    function setPrice(uint256 newPrice) external onlyOwner { price = newPrice; }
    function setMaxPerAgent(uint256 newMax) external onlyOwner { require(newMax > 0, "Max 0"); maxPerAgent = newMax; }
    function setAgentId(address newAgentId) external onlyOwner { require(newAgentId != address(0), "AgentID 0"); agentId = IERC721(newAgentId); }

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
