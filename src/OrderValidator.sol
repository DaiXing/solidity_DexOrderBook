// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./libraries/LibOrder.sol";

// 验证订单。
abstract contract OrderValidator {
    // 魔法值。
    bytes4 private constant EIP_1271_MAGIC_VALUE = 0x1626ba7e;
    // 订单取消。用最大值表示。
    uint256 private constant CANCELLED = type(uint256).max;

    // 已经成交的数量。
    // 用几个很大的值，表示特殊状态。
    // CANCELLED 取消的不能再处理。
    mapping(OrderKey => uint256) public filledAmount;

    // pad空间。升级占位。
    uint256[50] private __gap__;

    // 验证订单。
    function _validateOrder(
        LibOrder.Order memory order,
        bool isSkipExpiry
    ) internal view {
        require(order.maker != address(0), "maker invalid");
        require(order.salt != 0, "salt invalid");
        if (!isSkipExpiry) {
            require(
                order.expiry == 0 || order.expiry > block.timestamp,
                "expiry invalid"
            );
        }

        // 要价。卖家。
        if (order.side == LibOrder.Side.List) {
            require(order.nft.collection != address(0), "collection invalid");

            // todo 不判断价格？不判断tokenId ？
        }
        // 出价。买家。
        if (order.side == LibOrder.Side.Bid) {
            require(Price.unwrap(order.price) > 0, "price invalid");

            // todo 不判断 collection ？不判断tokenId ？
        }
    }

    // 读取。成交金额。
    function _getFilledAmount(
        OrderKey orderKey
    ) internal view returns (uint256 amount) {
        amount = filledAmount[orderKey];
        require(amount != CANCELLED, "CANCELLED");
    }

    // 更新。成交金额。
    function _updateFilledAmount(
        uint256 newAmount,
        OrderKey orderKey
    ) internal {
        require(newAmount != CANCELLED, "newAmount invalid");
        filledAmount[orderKey] = newAmount;
    }

    // 取消。成交金额。
    function _cancelFilledAmount(OrderKey orderKey) internal {
        filledAmount[orderKey] = CANCELLED;
    }
}
