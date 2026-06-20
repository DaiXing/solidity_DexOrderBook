// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../libraries/LibOrder.sol";

// 订单薄。
interface IOrderBook {
    // 创建订单。批量。卖家、买家都可以。
    // 返回，订单标识。
    function makeOrders(
        LibOrder.Order[] calldata orders // 一批订单
    ) external payable returns (OrderKey[] memory orderKeys);

    // 取消订单。批量。
    function cancelOrders(
        OrderKey[] calldata orderKeys // 一批订单
    ) external returns (bool[] memory successList);

    // 修改订单。批量。
    // 返回，新的OrderKey，因为字段修改了。
    function editOrders(
        LibOrder.EditDetail[] calldata orders // 一批订单
    ) external payable returns (OrderKey[] memory newOrderKeys);

    // 撮合订单。单个
    function matchOrder(
        LibOrder.Order calldata sellOrder, // 卖单
        LibOrder.Order calldata buyOrder // 买单
    ) external payable;

    // 撮合订单。批量。
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    ) external payable returns (bool[] memory successList);

    // 批量调用。
    //仅允许聚合 make/cancel/edit/match 相关函数，避免通过 multicall 调管理函数。
    // 在一次 multicall 中，最多只能包含 1 个“可能消耗 msg.value”的子调用（makeOrders/editOrders/matchOrder/matchOrders）。
    function multicall(
        bytes[] calldata datas, // 方法与参数。
        bool revertOnFail
    )
        external
        payable
        returns (bool[] memory successList, bytes[] memory results);
}
