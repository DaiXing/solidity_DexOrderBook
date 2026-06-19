// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibOrder.sol";

// 金库。保管 NFT和ETH。
interface IVault {
    // 查询order的余额。返回， eth金额，NFTtokenid
    function balanceOf(
        OrderKey orderKey
    ) external returns (uint256 ethAmount, uint256 tokenId);

    // 存款。 增加ETH。 只能买单。
    function depositeETH(OrderKey orderKey, uint256 ethAmount) external payable;

    // 取款。 订单需要有余额。  买单、卖单都可以。
    function withdrawETH(
        OrderKey orderKey,
        uint256 ethAmount,
        address to
    ) external;

    // 存款。 增加NFT。 只能卖单。
    function depositeNFT(
        OrderKey orderKey,
        address from, // token owner
        address collection,
        uint256 tokenId
    ) external;

    // 取款。 只能卖单。 被取消了。
    function withdrawNFT(
        OrderKey orderKey,
        address to, // send token to someone
        address collection,
        uint256 tokenId
    ) external;

    // 卖单。修改NFT
    function editNFT(OrderKey oldOrderKey, OrderKey newOrderKey) external;

    // 买单。修改eth
    function editETH(
        OrderKey oldOrderKey,
        OrderKey newOrderKey,
        uint256 oldEthAmount,
        uint256 newEthAmount,
        address to // send eth to someone
    ) external;

    // 转账 NFT。
    function transferERC721(
        address from, // token owner
        address to, // send to
        LibOrder.Asset calldata asset // nft
    ) external;

    // 转账 NFT。批量。
    function batchTransferERC721(
        address to, // send to
        LibOrder.NFTInfo[] calldata assets // nft
    ) external;
}
