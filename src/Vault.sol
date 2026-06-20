// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IVault.sol";
import "./libraries/LibOrder.sol";
import {
    LibTransferSafeUpgradeable,
    IERC721
} from "./libraries/LibTransferSafeUpgradeable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

// 金库。保管 NFT和ETH。
contract Vault is IVault, Ownable {
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    // 订单薄。
    address public orderBook;
    // 买单锁仓。 ETH
    mapping(OrderKey => uint256) ETHBalance;
    // 卖单锁仓。 NFT tokenId
    mapping(OrderKey => uint256) NFTBalance;

    // pad空间。升级占位。
    uint256[50] private __gap__;

    constructor() Ownable(address(this)) {}

    function initialize() public {
        // _owner = msg.sender;
        _transferOwnership(msg.sender);
    }

    // 只有订单薄才能操作。
    modifier onlyOrderBook() {
        require(msg.sender == orderBook, "not orderBook");
        _;
    }

    // 设置订单薄。
    function setOrderBook(address addr) public onlyOwner {
        orderBook = addr;
    }

    // 查询order的余额。返回， eth金额，NFTtokenid
    function balanceOf(
        OrderKey orderKey
    ) external view returns (uint256 ethAmount, uint256 tokenId) {
        ethAmount = ETHBalance[orderKey];
        tokenId = NFTBalance[orderKey];
    }

    // 存款。 增加ETH。 只能买单。
    function depositETH(OrderKey orderKey, uint256 ethAmount) external payable {
        require(msg.value > ethAmount, "eth not enough");
        // 增加eth。
        ETHBalance[orderKey] += msg.value;
    }

    // 取款。 订单需要有余额。  买单、卖单都可以。
    function withdrawETH(
        OrderKey orderKey,
        uint256 ethAmount,
        address to
    ) external {
        require(ethAmount > 0, "ethAmount invalid");

        ETHBalance[orderKey] -= ethAmount;
        to.safeTransferETH(ethAmount);
    }

    // 存款。 增加NFT。 只能卖单。
    function depositNFT(
        OrderKey orderKey,
        address from, // token owner
        address collection,
        uint256 tokenId
    ) external {
        require(tokenId > 0, "tokenId invalid");

        IERC721(collection).safeTransferFrom(from, address(this), tokenId);
        NFTBalance[orderKey] = tokenId;
    }

    // 取款。 只能卖单。 被取消了。
    function withdrawNFT(
        OrderKey orderKey,
        address to, // send token to someone
        address collection,
        uint256 tokenId
    ) external {
        require(tokenId > NFTBalance[orderKey], "tokenId invalid");

        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
        delete NFTBalance[orderKey];
    }

    // 卖单。修改NFT
    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external {
        // 简单的吧 tokenId 换个映射。
        NFTBalance[newOrderKey] = NFTBalance[oldOrderKey];
        delete NFTBalance[oldOrderKey];
    }

    // 买单。修改eth
    function editETH(
        OrderKey oldOrderKey,
        OrderKey newOrderKey,
        uint256 oldEthAmount,
        uint256 newEthAmount,
        address to // send eth to someone
    ) external payable {
        // 删除旧值。
        delete ETHBalance[oldOrderKey];

        // 设置新值。
        if (oldEthAmount > newEthAmount) {
            ETHBalance[newOrderKey] = newEthAmount;
            to.safeTransferETH(oldEthAmount - newEthAmount);
        } else if (oldEthAmount < newEthAmount) {
            require(
                msg.value >= newEthAmount - oldEthAmount,
                "msg.value not match"
            );
            ETHBalance[newOrderKey] = oldEthAmount + msg.value;
        } else {
            ETHBalance[newOrderKey] = oldEthAmount;
        }
    }

    // 转账 NFT。
    function transferERC721(
        address from, // token owner
        address to, // send to
        LibOrder.Asset calldata asset // nft
    ) external onlyOrderBook {
        IERC721(asset.collection).safeTransferFrom(from, to, asset.tokenId);
    }

    // 转账 NFT。批量。
    function batchTransferERC721(
        address to, // send to
        LibOrder.NFTInfo[] calldata assets // nft
    ) external {
        for (uint256 k = 0; k < assets.length; k++) {
            IERC721(assets[k].collection).safeTransferFrom(
                msg.sender,
                to,
                assets[k].tokenId
            );
        }
    }

    // 接收ETH
    receive() external payable {}

    // safeTransferFrom 需要这个。
    function onERC721Received() external payable returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
