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

    // 便于快速查到价格。 最优价，次优价。
    // NFT合约 -》 卖方买方 -》 全部的价格
    mapping(address => mapping(LibOrder.Side => RedBlackTreeLibrary.Tree))
        public priceTrees;

    // 多个订单，可以价格相同，所以用列表。便于找到需要的订单。
    // NFT合约 -》 卖方买方 -》 价格 -》 订单列表
    mapping(address => mapping(LibOrder.Side => mapping(Price => LibOrder.OrderQueue)))
        public orderQueues;

    // pad空间。升级占位。
    uint256[50] private __gap__;

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

    // 删除订单。
    // 成交后，从列表删除。
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

    // 查询订单。 分页。
    function getOrders(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind,
        uint256 count, // 多少个。
        Price price, // 价格档位。
        OrderKey firstOrderKey // 分页。从哪个元素开启取。
    )
        external
        returns (LibOrder.Order[] memory orderList, OrderKey nextOrderKey)
    {
        // 返回订单列表。
        orderList = new LibOrder.Order[](count);

        // 为空，取价格。
        if (RedBlackTreeLibrary.isEmpty(price)) {
            price = getBestPrice(collection, side);
        } else {
            // 没有开始元素，说明取完了。看下个价格。
            if (LibOrder.isSentinel(firstOrderKey)) {
                price = getNextBestPrice(collection, side, price);
            }
        }

        // 遍历一个价格。也就是一个队列。
        uint256 i;
        while (RedBlackTreeLibrary.isNotEmpty(price) && i < count) {
            // 队列。
            LibOrder.OrderQueue storage orderQueue = orderQueues[collection][
                side
            ][price];
            OrderKey orderKey = orderQueue.head;

            if (LibOrder.isNotSentinel(firstOrderKey)) {
                // 找到首个元素。
                while (
                    LibOrder.isNotSentinel(orderKey) &&
                    OrderKey.unwrap(firstOrderKey) != OrderKey.unwrap(orderKey)
                ) {
                    LibOrder.DBOrder storage order = orders[orderKey];
                    orderKey = order.next;
                }
                firstOrderKey = LibOrder.ORDERKEY_SENTINEL;
            }

            // 遍历链表。
            while (LibOrder.isNotSentinel(orderKey) && i < count) {
                LibOrder.DBOrder storage dbOrder = orders[orderKey];
                orderKey = dbOrder.next;

                // 订单过期了。忽略。
                if (
                    dbOrder.order.expiry != 0 &&
                    dbOrder.order.expiry < block.timestamp
                ) {
                    continue;
                }

                // 出价。买家。
                if (
                    side == LibOrder.Side.Bid &&
                    saleKind == LibOrder.SaleKind.FixedPriceForCollection
                ) {
                    // saleKind 不匹配。
                    if (
                        dbOrder.order.side == LibOrder.Side.Bid &&
                        dbOrder.order.saleKind ==
                        LibOrder.SaleKind.FixedPriceForItem
                    ) {
                        continue;
                    }
                }

                // 出价。买家。
                if (
                    side == LibOrder.Side.Bid &&
                    saleKind == LibOrder.SaleKind.FixedPriceForItem
                ) {
                    // tokenId 不匹配
                    if (
                        dbOrder.order.side == LibOrder.Side.Bid &&
                        dbOrder.order.saleKind ==
                        LibOrder.SaleKind.FixedPriceForItem &&
                        dbOrder.order.nft.tokenId != tokenId
                    ) {
                        continue;
                    }
                }

                // 满足条件。
                orderList[i] = dbOrder.order;
                i++;
                nextOrderKey = dbOrder.next;
            }

            // 当前队列，遍历完了。需要遍历下个队列。
            price = getNextBestPrice(collection, side, price);
        }
    }

    // 查找最好的订单。
    function getBestOrder(
        address collection,
        uint256 tokenId,
        LibOrder.Side side, // 卖家、买家
        LibOrder.SaleKind saleKind
    ) external returns (LibOrder.Order memory orderResult) {
        // 取最优价。
        Price price = getBestPrice(collection, side);

        // 有价格，就查询对于的列表。
        while (RedBlackTreeLibrary.isNotEmpty(price)) {
            LibOrder.OrderQueue storage orderQueue = orderQueues[collection][
                side
            ][price];

            OrderKey orderKey = orderQueue.head;

            // 遍历1个列表。
            while (LibOrder.isNotSentinel(orderKey)) {
                LibOrder.DBOrder storage dbOrder = orders[orderKey];
                orderKey = dbOrder.next;

                // 过期了。
                if (
                    dbOrder.order.expiry != 0 &&
                    dbOrder.order.expiry < block.timestamp
                ) {
                    continue;
                }

                // 出价。买家。
                if (
                    side == LibOrder.Side.Bid &&
                    saleKind == LibOrder.SaleKind.FixedPriceForItem
                ) {
                    // tokenId 不相同。
                    if (
                        dbOrder.order.side == LibOrder.Side.Bid &&
                        dbOrder.order.saleKind ==
                        LibOrder.SaleKind.FixedPriceForItem &&
                        tokenId != dbOrder.order.nft.tokenId
                    ) {
                        continue;
                    }
                }

                // 出价。买家。
                if (
                    side == LibOrder.Side.Bid &&
                    saleKind == LibOrder.SaleKind.FixedPriceForCollection
                ) {
                    // saleKind 不相同。
                    if (
                        dbOrder.order.side == LibOrder.Side.Bid &&
                        dbOrder.order.saleKind ==
                        LibOrder.SaleKind.FixedPriceForItem
                    ) {
                        continue;
                    }
                }

                // 其他情况。已经找到了
                orderResult = dbOrder.order;
                return orderResult;
            }

            // 当前列表，没有找到。继续看下个列表。
            price = getNextBestPrice(collection, side, price);
        }
    }
}
