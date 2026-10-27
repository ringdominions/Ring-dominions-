// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// Non-custodial fixed-price market: the NFT stays in the seller's wallet until sold.
contract CattyMarket is Ownable, ReentrancyGuard {
    struct Listing { uint256 tokenId; address seller; uint256 price; }

    IERC721 public immutable nft;
    uint256 public feeBps;            // 200 = 2%
    address public feeRecipient;
    uint256 public constant MAX_FEE_BPS = 1000; // 10% cap

    mapping(uint256 => Listing) public listings;
    uint256[] private _active;
    mapping(uint256 => uint256) private _pos; // tokenId => index+1

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event Cancelled(uint256 indexed tokenId);
    event Sold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price, uint256 fee);

    constructor(address nft_, uint256 feeBps_) Ownable(msg.sender) {
        require(nft_ != address(0), "NFT 0");
        require(feeBps_ <= MAX_FEE_BPS, "Fee too high");
        nft = IERC721(nft_);
        feeBps = feeBps_;
        feeRecipient = msg.sender;
    }

    function listItem(uint256 tokenId, uint256 priceWei) external {
        require(priceWei > 0, "Price 0");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");
        require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(tokenId) == address(this), "Not approved");
        listings[tokenId] = Listing(tokenId, msg.sender, priceWei);
        if (_pos[tokenId] == 0) { _active.push(tokenId); _pos[tokenId] = _active.length; }
        emit Listed(tokenId, msg.sender, priceWei);
    }

    function cancelListing(uint256 tokenId) external {
        Listing memory l = listings[tokenId];
        require(l.seller != address(0), "Not listed");
        // seller can cancel; anyone can clear a stale listing once seller no longer owns it
        require(msg.sender == l.seller || nft.ownerOf(tokenId) != l.seller, "Not seller");
        _remove(tokenId);
        emit Cancelled(tokenId);
    }

    function buyItem(uint256 tokenId) external payable nonReentrant {
        Listing memory l = listings[tokenId];
        require(l.seller != address(0), "Not listed");
        require(msg.value == l.price, "Wrong BNB amount");
        require(msg.sender != l.seller, "Own listing");
        _remove(tokenId);
        nft.safeTransferFrom(l.seller, msg.sender, tokenId);
        uint256 fee = (l.price * feeBps) / 10000;
        (bool ok1, ) = payable(l.seller).call{value: l.price - fee}("");
        require(ok1, "Pay seller failed");
        if (fee > 0) { (bool ok2, ) = payable(feeRecipient).call{value: fee}(""); require(ok2, "Fee failed"); }
        emit Sold(tokenId, l.seller, msg.sender, l.price, fee);
    }

    function getActiveListings() external view returns (Listing[] memory out) {
        out = new Listing[](_active.length);
        for (uint256 i = 0; i < _active.length; i++) out[i] = listings[_active[i]];
    }

    function setFee(uint256 bps) external onlyOwner { require(bps <= MAX_FEE_BPS, "Fee too high"); feeBps = bps; }
    function setFeeRecipient(address r) external onlyOwner { require(r != address(0), "0"); feeRecipient = r; }

    function _remove(uint256 tokenId) internal {
        delete listings[tokenId];
        uint256 p = _pos[tokenId];
        if (p == 0) return;
        uint256 last = _active[_active.length - 1];
        _active[p - 1] = last; _pos[last] = p;
        _active.pop(); delete _pos[tokenId];
    }
}
