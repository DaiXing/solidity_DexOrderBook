// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IOrderStorage.sol";
import {RedBlackTreeLibrary, Price} from "./libraries/RedBlackTreeLibrary.sol";
// import {
//     Initializable
// } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

error CannotInsertDuplicatedOrder(OrderKey orderKey);

// 订单的存储。
contract OrderStorage is IOrderStorage {
    // 红黑树。
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;

    // 订单信息。 key=订单key  value=订单+链表
    mapping(OrderKey => LibOrder.DBOrder) public orders;

    // 便于快速查到价格。
    // NFT合约 -》 卖方买方 -》 全部的价格
    mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree))
        public priceTrees;

    // 便于找到需要的订单。
    // NFT合约 -》 卖方买方 -》 价格 -》 订单列表
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue)))
        public orderQueues;

    // 取最好的价格。
    function getBestPrice(
        address collection,
        LibOrder.Side side
    ) public returns (Price price) {
        // 要价。卖家。 取最低价。
        if (side == LibOrder.Side.List) {
            return priceTrees[collection][side].first();
        }
        // 出价。买家。 取最高价。
        else {
            return priceTrees[collection][side].last();
        }
    }

    // 取相对最好的价格。
    function getNextBestPrice(
        address collection,
        LibOrder.Side side,
        Price price // 指定某个价格。比较。
    ) public returns (Price) {
        // 如果没有指定比较价格。就用全局最优价。
        if (RedBlackTreeLibrary.isEmpty(price)) {
            return getBestPrice(collection, side);
        }
        // 如果指定了比较价格，就取相对价格。
        // 要价。卖家。 往上找。
        if (side == LibOrder.Side.List) {
            return priceTrees[collection][side].next(price);
        }
        // 出价。买家。 往下找。
        else {
            return priceTrees[collection][side].prev(price);
        }
    }

    // 把订单插入红黑树。
    function _addOrder(
        LibOrder.Order memory order
    ) internal returns (OrderKey orderKey) {
        orderKey = LibOrder.hash(order);

        // 查询是否重复。
        if (orders[orderKey].order.maker != address(0)) {
            revert CannotInsertDuplicatedOrder(orderKey);
        }

        // 看价格。
        RedBlackTreeLibrary.Tree storage tree = priceTrees[
            order.nft.collection
        ][order.side];

        if (tree.exists(order.price)) {
            tree.insert(order.price); // 写入价格。
        }

        // 订单队列。
        LibOrder.OrderQueue storage orderQueue = orderQueues[
            order.nft.collection
        ][order.side][order.price];

        // 没有元素。初始化。
        if (LibOrder.isSentinel(orderQueue.head)) {
            orderQueues[order.nft.collection][order.side][
                order.price
            ] = LibOrder.OrderQueue({
                head: LibOrder.ORDERKEY_SENTINEL,
                tail: LibOrder.ORDERKEY_SENTINEL
            });
            orderQueue = orderQueues[order.nft.collection][order.side][
                order.price
            ];
        }

        // 当前的节点。
        orders[orderKey] = LibOrder.DBOrder({
            order: order,
            next: LibOrder.ORDERKEY_SENTINEL // 还没有后缀。
        });

        // 如果没有元素。
        if (LibOrder.isSentinel(orderQueue.tail)) {
            // 插入唯一的元素。
            orderQueue.head = orderKey;
            orderQueue.tail = orderKey;
        }
        // 如果有元素，就把当前元素放队列末尾。
        else {
            // 元素，末尾拼接。
            orders[orderQueue.tail].next = orderKey;
            orderQueue.tail = orderKey;
        }
    }

    function _removeOrder(
        LibOrder.Order memory order
    ) internal returns (OrderKey) {
        // 订单队列。
        LibOrder.OrderQueue storage orderQueue = orderQueues[
            order.nft.collection
        ][order.side][order.price];

        // 遍历列表。找到那个元素。
        OrderKey iterOrderKey = orderQueue.head;
        OrderKey prevOrderKey;
        bool found;
        while (!found && LibOrder.isNotSentinel(iterOrderKey)) {
            LibOrder.DBOrder storage order2 = orders[iterOrderKey];

            // 匹配全部字段。
            if (
                order2.order.maker == order.maker &&
                order2.order.side == order.side &&
                order2.order.saleKind == order.saleKind &&
                order2.order.nft.tokenId == order.nft.tokenId &&
                order2.order.nft.amount == order.nft.amount &&
                order2.order.expiry == order.expiry &&
                order2.order.salt == order.salt
            ) {
                found = true;
                break;
            }

            // 前一个元素。
            prevOrderKey = iterOrderKey;
            // 继续遍历。
            iterOrderKey = order2.next;
        }

        // 找到了。
        if (found) {
            LibOrder.DBOrder storage order2 = orders[iterOrderKey];

            // 如果元素是head
            if (
                OrderKey.unwrap(iterOrderKey) ==
                OrderKey.unwrap(orderQueue.head)
            ) {
                orderQueue.head = order2.next;
            }
            // 不是head
            else {
                orders[prevOrderKey].next = order2.next;
            }

            // 如果元素是tail
            if (
                OrderKey.unwrap(iterOrderKey) ==
                OrderKey.unwrap(orderQueue.tail)
            ) {
                orderQueue.tail = prevOrderKey;
            }

            // 如果列表空了。
            if (LibOrder.isSentinel(orderQueue.head)) {
                // 删除队列。
                delete orderQueues[order.nft.collection][order.side][
                    order.price
                ];

                // 删除价格。
                RedBlackTreeLibrary.Tree storage tree = priceTrees[
                    order.nft.collection
                ][order.side];
                if (tree.exists(order.price)) {
                    tree.remove(order.price);
                }
            }
        } else {
            // 没有找到。
            revert("order not found ");
        }
    }

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
