// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../multiSignature/multiSignatureClient.sol";
import "./DebtToken.sol"; // Adjust the path as necessary

using SafeERC20 for IERC20;



//主要业务实现
contract AstraLendPool is ReentrancyGuard, multiSignatureClient {

    enum PoolState{ MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE }
    //流动池信息，用于存放流动池的基本信息
    struct PoolBaseInfo {
        uint256 settleTime;         // 结算时间
        uint256 endTime;            // 结束时间
        uint256 interestRate;       // 池的固定利率，单位是1e8 (1e8)
        uint256 maxSupply;          // 池的最大限额
        uint256 lendSupply;         // 当前实际存款的借款
        uint256 borrowSupply;       // 当前实际存款的借款
        uint256 martgageRate;       // 池的抵押率，单位是1e8 (1e8)
        address lendToken;          // 出资方代币类型 (比如 BUSD..)
        address borrowToken;        // 借款方代币类型（代币合约地址） (比如 BTC..)
        PoolState state;            // 状态 'MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE'
        DebtToken spCoin;          // sp_token的erc20地址 (比如 spBUSD_1..)
        DebtToken jpCoin;          // jp_token的erc20地址 (比如 jpBTC_1..)
        uint256 autoLiquidateThreshold; // 自动清算阈值 (触发清算阈值)
    }
    //定义一个数组，用于存放所有的流动池信息
    PoolBaseInfo[] public poolBaseInfos;


    //流动池数据信息，用于存放流动池的详细信息
    struct PoolDataInfo{
        uint256 settleAmountLend;       // 结算时的实际出借金额
        uint256 settleAmountBorrow;     // 结算时的实际借款金额
        uint256 finishAmountLend;       // 完成时的实际出借金额
        uint256 finishAmountBorrow;     // 完成时的实际借款金额
        uint256 liquidationAmounLend;   // 清算时的实际出借金额
        uint256 liquidationAmounBorrow; // 清算时的实际借款金额
    }
    //定义一个数组，用于存放所有的流动池详细信息
    PoolDataInfo[] public poolDataInfos;

       // 借款用户信息
    struct BorrowInfo {
        uint256 stakeAmount;           // 当前借款的质押金额
        uint256 refundAmount;          // 多余的退款金额
        bool hasNoRefund;              // 默认为false，false = 未退款，true = 已退款
        bool hasNoClaim;               // 默认为false，false = 未认领，true = 已认领
    }
    // Info of each user that stakes tokens.  {user.address : {pool.index : user.borrowInfo}}
    mapping (address => mapping (uint256 => BorrowInfo)) public userBorrowInfo;

      // 出借方用户信息
    struct LendInfo {
        uint256 stakeAmount;          // 当前借款的质押金额
        uint256 refundAmount;         // 超额退款金额
        bool hasNoRefund;             // 默认为false，false = 无退款，true = 已退款
        bool hasNoClaim;              // 默认为false，false = 无索赔，true = 已索赔
    }

    // Info of each user that stakes tokens.  {user.address : {pool.index : user.lendInfo}}
    mapping (address => mapping (uint256 => LendInfo)) public userLendInfo;
    constructor(address multiSignatureAddress) multiSignatureClient(multiSignatureAddress) {
    }
}