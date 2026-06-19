// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library LibPayInfo {
    // 支付信息。
    struct PayInfo {
        address payable receiver; // 收款人。
        uint96 share; // 金额。扩了维度。
    }

    uint128 public constant TOTAL_SHARE = 10000; // 百分比的最大维度。
    uint128 public constant MAX_PROTOCOL_SHARE = TOTAL_SHARE;
    bytes32 public constant TYPE_HASH =
        keccak256("PayInfo(address payable receiver, uint96 share)");

    // 哈希。支付。
    function hash(PayInfo memory payInfo) public returns (bytes32 hashVal) {
        bytes memory buf = abi.encode(
            TYPE_HASH,
            payInfo.receiver,
            payInfo.share
        );
        hashVal = keccak256(buf);
    }
}
