// SPDX-License-Identifier: MIT
// FINAL — Ascension Catty (prepared 2026-11-17, NOT yet deployed)
// Changes vs the repo draft (contracts/AscensionCatty.sol):
//   - name "New NFT" -> "Ascension Catty", symbol "NNFT" -> "CATTY"
//   - PARALLEL LANES (user decision 2026-11-17): public mint is NO LONGER gated
//     behind the Agent phase. Both lanes run from the moment mint opens.
//     The 777 Agent seats stay reserved while the Agent phase is open
//     (tracked via agentMinted); endAgentPhase() releases the reservation.
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IBinanceAgentRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title Ascension Catty
/// @notice 1,111-token ERC-721. Two parallel lanes from launch: a free Agent ID
/// lane (777 seats reserved) and a public paid lane at 0.0012 BNB.
contract AscensionCatty is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 1111;
    uint256 public constant AGENT_SUPPLY = 777;
    uint256 public constant MAX_PER_WALLET = 10;
    uint256 public constant MAX_PER_AGENT_ID = 2;
    uint256 public constant PUBLIC_PRICE = 0.0012 ether;
    address public constant AGENT_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    uint256 public totalMinted;
    uint256 public agentMinted;
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
        ERC721("Ascension Catty", "CATTY")
        Ownable(msg.sender)
    {
        baseTokenURI = initialBaseURI;
    }

    /// @notice Free mint for a wallet that owns a Binance Agent ID NFT.
    function agentMint(uint256 quantity, uint256 agentId) external nonReentrant {
        require(mintOpen, "Mint is closed");
        require(agentPhaseOpen, "Agent phase ended");
        require(IBinanceAgentRegistry(AGENT_REGISTRY).ownerOf(agentId) == msg.sender, "Agent ID not owned");
        require(quantity > 0, "Quantity is zero");
        require(mintedByAgentId[agentId] + quantity <= MAX_PER_AGENT_ID, "Agent ID limit exceeded");
        require(mintedBy[msg.sender] + quantity <= MAX_PER_WALLET, "Wallet limit exceeded");
        require(agentMinted + quantity <= AGENT_SUPPLY, "Agent supply exhausted");
        require(totalMinted + quantity <= MAX_SUPPLY, "Sold out");

        uint256 firstTokenId = _mintTokens(msg.sender, quantity);
        mintedByAgentId[agentId] += quantity;
        agentMinted += quantity;
        emit AgentMinted(msg.sender, agentId, quantity, firstTokenId);
    }

    /// @notice Public mint, priced at 0.0012 BNB per NFT. Runs in parallel with
    /// the Agent lane; unclaimed Agent seats stay reserved while that phase is open.
    function mint(uint256 quantity) external payable nonReentrant {
        require(mintOpen, "Mint is closed");
        require(quantity > 0, "Quantity is zero");
        uint256 reserved = agentPhaseOpen ? AGENT_SUPPLY - agentMinted : 0;
        require(totalMinted + quantity <= MAX_SUPPLY - reserved, "Sold out");
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

    /// @notice Irreversibly ends the Agent phase and releases its seat reservation.
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
