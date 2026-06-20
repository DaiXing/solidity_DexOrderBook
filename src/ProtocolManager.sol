// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./libraries/LibOrder.sol";
import {LibPayInfo} from "./libraries/LibPayInfo.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// 手续费。
abstract contract ProtocolManager is Ownable {
    // 费率。抽成比。 万。
    uint128 public protocolShare;

    // 修改费率。
    event LogUpdatedProtocolShare(uint128 indexed newProtocolShare);

    // 修改费率。
    function setProtocolShare(uint128 newShare) public onlyOwner {
        require(newShare <= LibPayInfo.MAX_PROTOCOL_SHARE, "newShare invalid");

        protocolShare = newShare;
        emit LogUpdatedProtocolShare(newShare);
    }

    // 计算手续费。
    function _shareToAmount(
        uint128 total, // 总金额。
        uint128 share // 费率。
    ) internal pure returns (uint128) {
        return (total * share) / LibPayInfo.TOTAL_SHARE;
    }
}
