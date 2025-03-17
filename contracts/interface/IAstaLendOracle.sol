// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;


interface IAstraLendOracle {
    function getPrice(address _token) external view returns (uint256);
    function getPrices(address[] memory _tokens) external view returns (uint256[] memory);
}