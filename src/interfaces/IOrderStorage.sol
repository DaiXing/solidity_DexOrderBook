// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibOrder.sol";

// 订单存储。
interface IOrderStorage {
    // 查询订单。
    function getOrders(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind,
        uint256 count,
        Price price,
        OrderKey firstOrderKey
    ) external returns (LibOrder.Order[] memory orders, OrderKey nextOrderKey);

    // 查找最好的订单。
    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind
    ) external returns (LibOrder.Order memory order);
}
