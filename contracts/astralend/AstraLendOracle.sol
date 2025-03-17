// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../multiSignature/multiSignatureClient.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
contract AstraLendOracle is multiSignatureClient {


    //存放AggregatorV3Interface合约地址
    mapping(address => AggregatorV3Interface) internal priceFeeds;
    //存放精度
    mapping(address => uint256) internal decimals;
    //存放价格
    mapping(address => uint256) internal prices;


    constructor(address _multiSignature) multiSignatureClient(_multiSignature) {
    }

    // 价格查询
    function getPrice(address _token) public view returns (uint256) {
        AggregatorV3Interface priceFeed = priceFeeds[_token];
        if (address(priceFeed) == address(0)) {
            require(prices[_token] > 0, "AstraLendOracle: NO_PRICE");
            return prices[_token];
        }else {
            (, int price, , ,) = priceFeed.latestRoundData();
            uint256 decimal = decimals[_token];
            return uint256(price) / (10 ** decimal); 
        }
    }
    //多个价格查询
    function getPrices(address[] memory _tokens) public view returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _prices[i] = getPrice(_tokens[i]);
        }
        return _prices;
    }
    //设置代币以及对应的预言机地址
    function setFeedPrice(address token,address aggregator,uint256 _decimal)  public validCall{
        require(aggregator != address(0), "AstraLendOracle: INVALID_AGGREGATOR");
        require(_decimal > 0, "AstraLendOracle: INVALID_DECIMAL");
        priceFeeds[token] = AggregatorV3Interface(aggregator);
        decimals[token] = _decimal;
    }
    //自定义价格设置
    function setPrice(address token,uint256 _price) public validCall{
        require(_price > 0, "AstraLendOracle: INVALID_PRICE");
        prices[token] = _price;
    }
}