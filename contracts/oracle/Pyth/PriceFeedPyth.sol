// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "../../libraries/math/SafeMathInt.sol";
import "./IPyth.sol";
import "./PythStructs.sol";
import "../interfaces/IPriceFeed.sol";
pragma experimental ABIEncoderV2;

contract PriceFeedPyth is IPriceFeed {
    using SafeMathInt for int256;
    IPyth public pyth;
    bytes32 public priceID;
    string public override description = "PriceFeed";
    address public override aggregator;
    int256 public constant CHAIN_LINK_PRICE_PRECISION = 10 ** 8;

    constructor(address pythContract, bytes32 priceID_) public {
        pyth = IPyth(pythContract);
        priceID = priceID_;
    }

    function latestRound() public view override returns (uint80) {
        return 1;
    }

    function getRoundData(
        uint80 /* _roundId */
    )
      external
      view
      override
      returns (
          uint80 /* roundId */,
          int256 /* answer */,
          uint256 /* startedAt */,
          uint256 /* updatedAt */,
          uint80 /* answeredInRound */
      )
    {
        revert("UseLatestRoundToGetDataFeedPrice");
    }

    function latestAnswer() external view override returns (int256) {
        PythStructs.PriceFeed memory priceFeed = pyth.queryPriceFeed(priceID);
        int256 price = int256(priceFeed.price.price);
        require(priceFeed.price.expo<0,"invalid expo");
        uint256 pythPricePrecision = uint256(10)**uint256(uint32(-priceFeed.price.expo));
        return price.mul(CHAIN_LINK_PRICE_PRECISION).div(int256(pythPricePrecision));
    }

    function latestAnswersById(
        bytes32 pId
    ) external view returns (PythStructs.PriceFeed memory price) {
        return pyth.queryPriceFeed(pId);
    }

}
