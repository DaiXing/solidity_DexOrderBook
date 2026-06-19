// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibOrder.sol";

// 订单存储。
interface IOrderStorage {
    // 查询订单。 分页。
    function getOrders(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind,
        uint256 count, // 多少个。
        Price price, // 价格档位。
        OrderKey firstOrderKey // 分页。从哪个元素开启取。
    ) external returns (LibOrder.Order[] memory orders, OrderKey nextOrderKey);

    // 查找最好的订单。
    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind
    ) external returns (LibOrder.Order memory order);
}
