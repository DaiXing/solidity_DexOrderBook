// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Price} from "./RedBlackTreeLibrary.sol";

// 标识订单。来自订单的字段。
type OrderKey is bytes32; // hash 256

library LibOrder {
    // 哪个方向。
    enum Side {
        // todo 只能是被动方？
        List, // 挂单。 卖家。就是 ask 要价。
        Bid // 出价。 买家
    }
    // 售卖类型。
    enum SaleKind {
        FixedPriceForCollection, // 限价。针对整个集合。
        FixedPriceForItem // 限价。针对单个token
    }
    // 资产。
    struct Asset {
        uint256 tokenId; // NFT币
        address collection; // 集合。地址。
        uint96 amount; // 数量
    }
    // NFT信息。
    struct NFTInfo {
        address collection; // 集合。地址。
        uint256 tokenId; // NFT币
    }
    // 订单。
    struct Order {
        Side side; // 区分卖家、买家
        SaleKind saleKind; // 买单个token？
        address maker; // 创建者。挂单者。可以是卖家、买家。
        Asset nft; // NFT资产
        Price price; // 价格
        uint64 expiry; // 过期时间。
        uint64 salt; // 加盐
    }
    // 订单，存储在链表。
    struct DBOrder {
        Order order;
        OrderKey next; // 链表的下个。
    }
    // 链表。
    struct OrderQueue {
        OrderKey head;
        OrderKey tail;
    }
    // 修改订单。 改了订单字段，OrderKey就跟着改了。
    struct EditDetail {
        OrderKey oldOrderKey; // 旧订单key
        Order newOrder; // 新订单明细。
    }
    // 撮合订单。
    // 用side区分卖家、买家。
    struct MatchDetail {
        Order sellOrder;
        Order buyOrder;
    }
    // 常量。
    OrderKey public constant ORDERKEY_SENTINEL = OrderKey.wrap(0x0);
    bytes32 public constant ASSET_TYPEHASH =
        keccak256("Asset(uint256 tokenId,address collection,uint96 amount)");
    bytes32 public constant ORDER_TYPEHASH =
        keccak256(
            "Order(uint8 side,uint8 saleKind,address maker,Asset nft,uint128 price,uint64 expiry,uint64 salt)Asset(uint256 tokenId,address collection,uint96 amount)"
        );
    Price public constant PRICE_EMPTY = Price.wrap(0);

    // 哈希。 资产。
    function hash(Asset memory asset) internal pure returns (bytes32) {
        // 编码。包含字段。
        bytes memory buf = abi.encode(
            ASSET_TYPEHASH,
            asset.tokenId,
            asset.collection,
            asset.amount
        );
        bytes32 hashVal = keccak256(buf);
        return hashVal;
    }

    // 哈希。 订单。
    function hash(Order memory order) internal pure returns (OrderKey) {
        // 编码。包含字段。
        bytes memory buf = abi.encode(
            ORDER_TYPEHASH,
            order.side,
            order.saleKind,
            order.maker,
            hash(order.nft),
            Price.unwrap(order.price),
            order.expiry,
            order.salt
        );
        bytes32 hashVal = keccak256(buf);
        return OrderKey.wrap(hashVal); // 转换类型。
    }

    function isSentinel(OrderKey orderKey) public pure returns (bool) {
        return OrderKey.unwrap(orderKey) == OrderKey.unwrap(ORDERKEY_SENTINEL);
    }

    function isNotSentinel(OrderKey orderKey) public pure returns (bool) {
        return !isSentinel(orderKey);
    }
}
