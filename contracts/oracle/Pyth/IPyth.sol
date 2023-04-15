// SPDX-License-Identifier: MIT

pragma solidity >= 0.6.12;

import "./PythStructs.sol";
pragma experimental ABIEncoderV2;

interface IPyth {
    function queryPriceFeed(
        bytes32 id
    ) external view returns (PythStructs.PriceFeed memory priceFeed);

    function priceFeedExists(
        bytes32 id
    ) external view returns (bool);
}
