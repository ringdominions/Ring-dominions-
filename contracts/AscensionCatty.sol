// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IBinanceAgentRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title New NFT Collection
/// @notice 1,111-token ERC-721 with an Agent ID phase followed by public mint.
contract AscensionCatty is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 1111;
    uint256 public constant AGENT_SUPPLY = 777;
    uint256 public constant MAX_PER_WALLET = 10;
    uint256 public constant MAX_PER_AGENT_ID = 2;
    uint256 public constant PUBLIC_PRICE = 0.0012 ether;
    address public constant AGENT_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    uint256 public totalMinted;
    bool public mintOpen;
    bool public agentPhaseOpen = true;
    string private baseTokenURI;
    mapping(address => uint256) public mintedBy;
    mapping(uint256 => uint256) public mintedByAgentId;

    event AgentMinted(address indexed to, uint256 indexed agentId, uint256 quantity, uint256 firstTokenId);
    event PublicMinted(address indexed to, uint256 quantity, uint256 firstTokenId);
    event MintStatusChanged(bool open);
    event AgentPhaseEnded();
    event BaseURIChanged(string newBaseURI);

    constructor(string memory initialBaseURI)
        ERC721("New NFT", "NNFT")
        Ownable(msg.sender)
    {
        baseTokenURI = initialBaseURI;
    }

    /// @notice Free mint for a wallet that owns a Binance Agent ID NFT.
    function agentMint(uint256 quantity, uint256 agentId) external nonReentrant {
        require(mintOpen, "Mint is closed");
        require(agentPhaseOpen && totalMinted < AGENT_SUPPLY, "Agent phase ended");
        require(IBinanceAgentRegistry(AGENT_REGISTRY).ownerOf(agentId) == msg.sender, "Agent ID not owned");
        require(quantity > 0, "Quantity is zero");
        require(mintedByAgentId[agentId] + quantity <= MAX_PER_AGENT_ID, "Agent ID limit exceeded");
        require(mintedBy[msg.sender] + quantity <= MAX_PER_WALLET, "Wallet limit exceeded");
        require(totalMinted + quantity <= AGENT_SUPPLY, "Agent supply exhausted");

        uint256 firstTokenId = _mintTokens(msg.sender, quantity);
        mintedByAgentId[agentId] += quantity;
        emit AgentMinted(msg.sender, agentId, quantity, firstTokenId);
    }

    /// @notice Public mint after the Agent phase, priced at 0.0012 BNB per NFT.
    function mint(uint256 quantity) external payable nonReentrant {
        require(mintOpen, "Mint is closed");
        require(!agentPhaseOpen || totalMinted >= AGENT_SUPPLY, "Public mint not open");
        require(quantity > 0, "Quantity is zero");
        require(totalMinted + quantity <= MAX_SUPPLY, "Sold out");
        require(mintedBy[msg.sender] + quantity <= MAX_PER_WALLET, "Wallet limit exceeded");
        require(msg.value == PUBLIC_PRICE * quantity, "Incorrect payment");

        uint256 firstTokenId = _mintTokens(msg.sender, quantity);
        emit PublicMinted(msg.sender, quantity, firstTokenId);
    }

    function _mintTokens(address to, uint256 quantity) internal returns (uint256 firstTokenId) {
        firstTokenId = totalMinted + 1;
        mintedBy[to] += quantity;
        totalMinted += quantity;
        for (uint256 i = 0; i < quantity; i++) {
            _safeMint(to, firstTokenId + i);
        }
    }

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintStatusChanged(open);
    }

    /// @notice Irreversibly ends the Agent phase and enables public mint.
    function endAgentPhase() external onlyOwner {
        require(agentPhaseOpen, "Agent phase already ended");
        agentPhaseOpen = false;
        emit AgentPhaseEnded();
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
