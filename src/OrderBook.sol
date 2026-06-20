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
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// 订单薄。
contract OrderBook is
    IOrderBook,
    OrderStorage,
    OrderValidator,
    ProtocolManager,
    Ownable,
    Pausable,
    ReentrancyGuard
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

    // 只允许 delegatecall 调用。
    modifier onDelegateCall() {
        _checkDelegateCall();
        _;
    }
    function _checkDelegateCall() {
        // todo
    }

    // 自身。
    address public immutable self = address(this);
    // 金库。
    address private _vault;

    function initialize() {
        // _owner = msg.sender;
        _transferOwnership(msg.sender);
    }

    // 创建订单。批量。卖家、买家都可以。
    // 返回，订单标识。
    function makeOrders(
        LibOrder.Order[] calldata orders // 一批订单
    )
        external
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory orderKeys)
    {
        uint256 orderCount = orders.length;
        orderKeys = new OrderKey[](orderCount);

        // 买单，累加eth。
        uint256 ethSum = 0;

        // 遍历。
        for (uint256 k = 0; k < orderCount; k++) {
            LibOrder.Order calldata order = orders[k];

            uint128 buyPrice = 0;

            // 买单。
            if (order.side == LibOrder.Side.Bid) {
                buyPrice = Price.unwrap(order.price) * order.nft.amount;
            }

            // 创建订单。
            OrderKey orderKey = _makeOrderTry(order, buyPrice);
            orderKeys[k] = orderKey;

            // 有效订单。
            if (
                OrderKey.unwrap(orderKey) !=
                OrderKey.unwrap(OrderKey.ORDERKEY_SENTINEL)
            ) {
                ethSum += buyPrice;
            }
        }

        // eth 给多了。返回。
        if (msg.value > buyPrice) {
            payable(msg.sender).safeTransferETH(msg.value - buyPrice);
        }
    }

    // 尝试，创建订单。
    // 1、校验字段
    // 2、金库。存NFT、ETH
    // 3、存储。存价格、链表
    function _makeOrderTry(
        LibOrder.Order calldata order,
        uint128 ethAmount
    ) internal returns (OrderKey newOrderKey) {
        newOrderKey = LibOrder.hash(order);

        // 判断字段。
        if (
            order.maker == msg.sender && // 必须自己
            Price.unwrap(order.price) != 0 && // price
            order.salt != 0 && // salt
            (order.expiry == 0 || order.expiry > block.timestamp) && // time
            filledAmount[newOrderKey] == 0 // 没有成交记录
        ) {
            // 操作金库。
            // 卖单。 判断NFT
            if (order.side == LibOrder.Side.List) {
                // 卖单，只能有1个NFT.
                if (order.nft.amount != 1) {
                    return LibOrder.ORDERKEY_SENTINEL;
                }

                // NFT 存金库。
                IVault(_vault).depositeNFT(
                    newOrderKey,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            }
            // 买单。 判断ETH
            else if (order.side == LibOrder.Side.Bid) {
                // 买单，必须有多个数量。
                if (order.nft.amount == 0) {
                    return LibOrder.ORDERKEY_SENTINEL;
                }

                // ETH 存金库。
                // eth 必须使用 msg.value 传递金额。
                IVault(_vault).depositeETH{value: uint256(ethAmount)}(
                    newOrderKey,
                    ethAmount
                ); //
            }

            // 操作存储。
            _addOrder(order);

            // 事件。
            emit LogMake(
                newOrderKey,
                order.side,
                order.saleKind,
                order.maker,
                order.nft,
                order.price,
                order.expiry,
                order.salt
            );
        } else {
            emit LogSkipOrder(newOrderKey, order.salt);

            return LibOrder.ORDERKEY_SENTINEL;
        }
    }

    // 取消订单。批量。
    function cancelOrders(
        OrderKey[] calldata orderKeys // 一批订单
    ) external whenNotPaused nonReentrant returns (bool[] memory successList) {
        uint256 orderCount = orderKeys.length;
        successList = new bool[](orderCount);

        for (uint256 m = 0; m < orderCount; m++) {
            bool ok = _cancelOrderTry(orderKeys[m]);
            successList[m] = ok;
        }
    }

    // 取消订单。尝试。
    function _cancelOrderTry(
        OrderKey orderKey
    ) internal returns (bool success) {
        LibOrder.Order memory order = orders[orderKey];
        if (
            order.maker == msg.sender && // 只能自己
            filledAmount[orderKey] < order.nft.amount // 没有完全成交
        ) {
            // 存储。删除order
            _removeOrder(order);

            // 卖单。退回NFT
            if (order.side == LibOrder.Side.List) {
                IVault(_vault).withdrawNFT(
                    orderKey,
                    order.maker, // send token to someone
                    order.nft.collection,
                    order.nft.tokenId
                );
            }
            // 买单。退回ETH
            else if (order.side == LibOrder.Side.Bid) {
                uint256 leftNftAmount = order.nft.amount -
                    filledAmount[orderKey];

                IVault(_vault).withdrawETH(
                    orderKey,
                    leftNftAmount * Price.unwrap(order.price),
                    order.maker
                );
            }

            // 设置取消标记。
            _cancelFilledAmount(orderKey);

            success = true;
            emit LogCancel(orderKey, order.maker);
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }
    }

    // 修改订单。批量。
    // 返回，新的OrderKey，因为字段修改了。
    function editOrders(
        LibOrder.EditDetail[] calldata orders // 一批订单
    )
        external
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory newOrderKeys)
    {
        uint256 orderCount = orders.length;
        newOrderKeys = new OrderKey[](orderCount);

        // eth 差额。
        uint256 sumBidPrice = 0;
        for (uint256 m = 0; m < orderCount; m++) {
            // 修改。
            (OrderKey newOrderKey, uint256 needBidPrice) = _editOrderTry(
                orders[m].oldOrderKey,
                orders[m].newOrder
            );

            newOrderKeys[m] = newOrderKey;
            sumBidPrice += needBidPrice;
        }

        // 如果用户给多了，需要退回。
        if (msg.value > sumBidPrice) {
            payable(msg.sender).safeTransferETH(msg.value - sumBidPrice);
        }
    }

    // 修改订单。尝试。
    function _editOrderTry(
        OrderKey oldOrderKey,
        LibOrder.Order calldata newOrder
    ) internal returns (OrderKey newOrderKey, Price deltaBidPrice) {
        LibOrder.Order memory oldOrder = orders[oldOrderKey];
        OrderKey newOrderKey = LibOrder.hash(newOrder);
        uint256 oldFilledAmount = filledAmount[oldOrderKey];

        // todo oldFilledAmount 只存成交数量？不存成交金额？

        // 只能修改价格、数量
        if (
            oldOrder.side != newOrder.side ||
            oldOrder.saleKind != newOrder.saleKind ||
            oldOrder.maker != newOrder.maker ||
            oldOrder.nft.collection != newOrder.nft.collection ||
            oldOrder.nft.tokenId != newOrder.nft.tokenId ||
            filledAmount[oldOrderKey] >= oldOrder.nft.amount // 不能都成交。
        ) {
            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }

        // 检查 新订单的字段
        if (
            newOrder.maker != msg.sender ||
            newOrder.salt == 0 ||
            (newOrder.expiry != 0 && newOrder.expiry < block.timestamp) ||
            filledAmount[newOrderKey] != 0 // 不能有记录。
        ) {
            emit LogSkipOrder(newOrderKey, newOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }

        // 存储。 把订单放入集合。
        newOrderKey = _addOrder(newOrder);

        // 金库。

        // 卖单。 处理 NFT
        if (newOrder.side == LibOrder.Side.List) {
            // 修改NFT的关联。
            IVault(_vault).editNFT(oldOrderKey, newOrderKey);
        }
        // 买单。 处理 ETH
        else if (newOrder.side == LibOrder.Side.Bid) {
            uint256 oldRemainingPrice = Price.unwrap(oldOrder.price) *
                (oldOrder.nft.amount - oldFilledAmount);
            uint256 newRemainingPrice = Price.unwrap(newOrder.price) *
                (newOrder.nft.amount);

            // todo 真实成交价，可能不等于 order.price 。 能直接 price * amount ?

            // 新价格更高。补足差额。
            if (newRemainingPrice > oldRemainingPrice) {
                deltaBidPrice = newRemainingPrice - oldRemainingPrice;
            }
            // 修改ETH
            IVault(_vault).editETH{value: deltaBidPrice}(
                oldOrderKey,
                newOrderKey,
                oldRemainingPrice,
                newRemainingPrice,
                newOrder.maker
            );
        }
    }

    // 判断2个订单，是否可以撮合。
    function _isMatchAvailable(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        OrderKey sellOrderKey,
        OrderKey buyOrderKey
    ) internal {
        // 不能是同一个订单。
        require(
            OrderKey.unwrap(sellOrderKey) != OrderKey.unwrap(buyOrderKey),
            "same order"
        );
        // 不能属于同一个人。
        require(sellOrder.maker != buyOrder.maker, "same maker");
        // 卖单、买单
        require(
            sellOrder.side == LibOrder.Side.List &&
                buyOrder.side == LibOrder.Side.Bid,
            "side invalid"
        );
        // 只能卖单个。
        require(
            sellOrder.saleKind == LibOrder.SaleKind.FixedPriceForItem,
            "saleKind invalid"
        );
        // 资产。
        require(
            buyOrder.saleKind == LibOrder.SaleKind.FixedPriceForCollection ||
                (sellOrder.nft.collection == buyOrder.nft.collection &&
                    sellOrder.nft.tokenId == buyOrder.nft.tokenId),
            "assert not match"
        );
        // 处理完成了。
        require(
            filledAmount[sellOrderKey] < sellOrder.nft.amount &&
                filledAmount[buyOrderKey] < buyOrder.nft.amount,
            "filledAmount invalid"
        );
    }

    // 撮合订单。单个
    function _matchOrder(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        uint128 msgValue
    ) internal returns (uint128 costValue) {
        OrderKey sellOrderKey = LibOrder.hash(sellOrder);
        OrderKey buyOrderKey = LibOrder.hash(buyOrder);

        // 判断。
        _isMatchAvailable(sellOrder, buyOrder, sellOrderKey, buyOrderKey);

        // 如果自己是卖家。
        if (msg.sender == sellOrder.maker) {
            // 卖家不需要支付eth
            require(msgValue == 0, "msgValue invalid ");

            bool isSellExist = orders[sellOrderKey].order.maker != 0;

            // todo  第二个参数，为什么用 isSellExist ？
            _validateOrder(sellOrder, isSellExist);
            _validateOrder(orders[buyOrderKey].order, false);

            // 成交价。 使用 买单 的价格。
            uint128 fillPrice = Price.unwrap(buyOrder.price);

            // 成交了。

            // 更新 卖单
            if (isSellExist) {
                // 移除。
                _removeOrder(sellOrder);
                // 卖单。 只能卖1个，直接更新了。
                _updateFilledAmount(sellOrder.nft.amount, sellOrderKey);
            }

            // 更新 买单
            // 因为卖单只卖1个，所以买单本次只能买1个。
            _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);

            emit LogMatch(
                sellOrderKey,
                buyOrderKey,
                sellOrder,
                buyOrder,
                fillPrice
            );

            //----------------------
            // 金库。

            // 买家把ETH给订单薄。 扣除手续费后，才能给卖家。
            IVault(_vault).withdrawETH(buyOrderKey, fillPrice, address(this));

            // 手续费。
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);

            // 把剩余的eth，给卖家。
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);

            if (isSellExist) {
                // 卖家把NFT给买家。
                IVault(_vault).withdrawNFT(
                    sellOrderKey, // owner
                    buyOrder.maker, // send to
                    sellOrder.nft.collection,
                    sellOrder.nft.tokenId
                );
            } else {
                // 卖单不在存储。直接转。
                IVault(_vault).transferERC721(
                    sellOrder.maker, // 卖家
                    buyOrder.maker, // 买家
                    sellOrder.nft // nft
                );
            }
        }
        // 如果自己是买家。
        else if (msg.sender == buyOrder.maker) {
            bool isBuyExist = orders[buyOrderKey].order.maker != address(0);

            _validateOrder(buyOrder, isBuyExist);
            _validateOrder(orders[sellOrderKey].order, false);

            // 成交价。使用卖单价格。
            uint128 fillPrice = Price.unwrap(sellOrder.price);

            // 出价。
            uint128 buyPrice = Price.unwrap(buyOrder.price);

            // 买单出价，必须大于，卖单要价。
            if (!isBuyExist) {
                // 如果买单不在存储，则需要带上足够的eth
                require(msgValue > fillPrice, "msgValue not enough");
            } else {
                // 价格必须足够。
                require(buyPrice > fillPrice, "buyPrice not enough");

                // 把买单的ETH转到本合约。
                // todo 这里为啥不用 fillPrice ？
                // todo 买单每个，只能买1个卖单？
                IVault(_vault).withdrawETH(
                    buyOrderKey,
                    buyPrice,
                    address(this)
                );

                // todo 买单可以买多个token，这里买了1个就删除了？
                _removeOrder(buyOrder);

                // 更新 买单
                // 因为卖单只卖1个，所以买单本次只能买1个。
                _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);
            }

            // 移除。
            // todo 不移除卖单？
            // _removeOrder(sellOrder);
            // 卖单。 只能卖1个，直接更新了。
            _updateFilledAmount(sellOrder.nft.amount, sellOrderKey);

            emit LogMatch(
                buyOrderKey,
                sellOrderKey,
                buyOrder,
                sellOrder,
                fillPrice
            );

            // 手续费。
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);

            // 扣除手续费，把剩余eth给卖家。
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);

            // 买家给多了，退回。
            if (buyPrice > fillPrice) {
                buyOrder.maker.safeTransferETH(buyPrice - fillPrice);
            }

            // 卖家把NFT给买家。
            IVault(_vault).withdrawNFT(
                sellOrderKey, // owner
                buyOrder.maker, // send to
                sellOrder.nft.collection,
                sellOrder.nft.tokenId
            );

            // 已经在存储，直接从存储扣费。否则，实时扣费。
            costValue = isBuyExist ? 0 : buyPrice;
        } else {
            revert("send invalid");
        }
    }

    // 撮合订单。单个
    function matchOrder(
        LibOrder.Order calldata sellOrder, // 卖单
        LibOrder.Order calldata buyOrder // 买单
    ) external payable whenNotPaused nonReentrant {
        // 撮合订单。
        uint128 costValue = _matchOrder(sellOrder, buyOrder, msg.value);

        // 用户给多了，退回eth 。
        if (msg.value > costValue) {
            msg.sender.safeTransferETH(msg.value - costValue);
        }
    }

    // 撮合订单。批量。
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    ) external whenNotPaused nonReentrant returns (bool[] memory successList) {}

    // 批量调用。
    //仅允许聚合 make/cancel/edit/match 相关函数，避免通过 multicall 调管理函数。
    // 在一次 multicall 中，最多只能包含 1 个“可能消耗 msg.value”的子调用（makeOrders/editOrders/matchOrder/matchOrders）。
    function multicall(
        bytes[] calldata datas, // 方法与参数。
        bool revertOnFail
    )
        external
        payable
        returns (bool[] memory successList, bytes[] memory results)
    {}
}
