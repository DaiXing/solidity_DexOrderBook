// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IOrderBook.sol";
import "./libraries/LibOrder.sol";
import "./OrderStorage.sol";
import "./OrderValidator.sol";
import "./Vault.sol";
import "./ProtocolManager.sol";
import "./libraries/LibPayInfo.sol";

import {
    LibTransferSafeUpgradeable,
    IERC721
} from "./libraries/LibTransferSafeUpgradeable.sol";

// 订单薄。
contract OrderBook is
    IOrderBook,
    OrderStorage,
    OrderValidator,
    ProtocolManager
{
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    // 创建订单。
    event LogMake(
        OrderKey orderKey,
        LibOrder.Side indexed side,
        LibOrder.SaleKind indexed saleKind,
        address indexed maker, // 创建者。
        LibOrder.Asset nft,
        Price price,
        uint64 expiry,
        uint64 salt
    );
    // 取消订单。
    event LogCancel(
        OrderKey indexed orderKey,
        address indexed maker // 创建者。
    );
    // 匹配订单。
    event LogMatch(
        OrderKey indexed makeOrderKey, // 挂单。
        OrderKey indexed takeOrderKey, // 吃单。
        LibOrder.Order makeOrder, // 挂单。
        LibOrder.Order takeOrder, // 吃单。
        uint128 fillPrice // 成交价格。
    );
    // 取款。eth
    event LogWithdrawETH(address to, uint256 amount);
    // 批量匹配。内部错误。
    event BatchMatchInnerError(uint256 offset, bytes msg);
    // 批量call。内部错误。
    event MulticallInnerError(uint256 offset, bytes msg);
    // 跳过订单。
    event LogSkipOrder(OrderKey orderKey, uint64 salt);

    // 创建订单。批量。卖家、买家都可以。
    // 返回，订单标识。
    function makeOrders(
        LibOrder.Order[] calldata orders // 一批订单
    ) external returns (OrderKey[] memory orderKeys);

    // 取消订单。批量。
    function cancelOrders(
        OrderKey[] calldata orderKeys // 一批订单
    ) external returns (bool[] memory successList);

    // 修改订单。批量。
    // 返回，新的OrderKey，因为字段修改了。
    function editOrders(
        LibOrder.Order[] calldata orders // 一批订单
    ) external returns (OrderKey[] memory newOrderKeys);

    // 撮合订单。单个
    function matchOrder(
        LibOrder.Order calldata sellOrder, // 卖单
        LibOrder.Order calldata buyOrder // 买单
    ) external payable;

    // 撮合订单。批量。
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    ) external returns (bool[] memory successList);

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
