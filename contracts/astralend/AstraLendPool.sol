// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../multiSignature/multiSignatureClient.sol";
import "./DebtToken.sol"; 
import "../interface/IAstraLendOracle.sol";

using SafeERC20 for IERC20;

//主要业务实现
contract AstraLendPool is ReentrancyGuard, multiSignatureClient {
    //全局暂停状态
    bool public globalPaused = false;

    //存款最小限额
    uint256 public minAmount = 100e18;

    //计算精度
    uint256 constant internal calDecimal = 1e18;

    //预言机地址
    IAstraLendOracle public oracle;

    enum PoolState{ MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE }
    //流动池信息，用于存放流动池的基本信息
    struct PoolBaseInfo {
        uint256 settleTime;         // 结算时间
        uint256 endTime;            // 结束时间
        uint256 interestRate;       // 池的固定利率，单位是1e8 (1e8)
        uint256 maxSupply;          // 池的最大限额
        uint256 lendSupply;         // 当前实际存款的借款
        uint256 borrowSupply;       // 当前实际存款的借款
        uint256 mortgageRate;       // 池的抵押率，单位是1e8 (1e8)
        address lendToken;          // 出资方代币类型 (比如 BUSD..)
        address borrowToken;        // 借款方代币类型（代币合约地址） (比如 BTC..)
        PoolState state;            // 状态 'MATCH, EXECUTION, FINISH, LIQUIDATION, UNDONE'
        DebtToken spCoin;          // sp_token的erc20地址 (比如 spBUSD_1..)
        DebtToken jpCoin;          // jp_token的erc20地址 (比如 jpBTC_1..)
        uint256 autoLiquidateThreshold; // 自动清算阈值 (触发清算阈值)
    }
    //定义一个数组，用于存放所有的流动池信息
    PoolBaseInfo[] public poolBaseInfos;    



    //流动池数据信息
    struct PoolDataInfo{
        uint256 settleAmountLend;       // 结算时的实际出借金额
        uint256 settleAmountBorrow;     // 结算时的实际借款金额
        uint256 finishAmountLend;       // 完成时的实际出借金额
        uint256 finishAmountBorrow;     // 完成时的实际借款金额
        uint256 liquidationAmounLend;   // 清算时的实际出借金额
        uint256 liquidationAmounBorrow; // 清算时的实际借款金额
    }
    //定义一个数组，用于存放所有的流动池详细数据信息
    PoolDataInfo[] public poolDataInfos;

       // 借款用户信息
    struct BorrowInfo {
        uint256 stakeAmount;           // 当前借款的质押金额
        uint256 refundAmount;          // 多余的退款金额
        bool hasNoRefund;              // 默认为false，false = 未退款，true = 已退款
        bool hasNoClaim;               // 默认为false，false = 未认领，true = 已认领
    }
    // 借款方信息 {user.address : {pool.index : user.borrowInfo}}
    mapping (address => mapping (uint256 => BorrowInfo)) public userBorrowInfo;

      // 存款方用户信息
    struct LendInfo {
        uint256 stakeAmount;          // 当前存款的质押金额
        uint256 refundAmount;         // 超额退款金额
        bool hasNoRefund;             // 默认为false，false = 无退款，true = 已退款
        bool hasNoClaim;              // 默认为false，false = 无索赔，true = 已索赔
    }

    // 借款方信息   {user.address : {pool.index : user.lendInfo}}
    mapping (address => mapping (uint256 => LendInfo)) public userLendInfo;
    constructor(address multiSignatureAddress) multiSignatureClient(multiSignatureAddress) {
    }

    event DepositLend(address from, address lendToken, uint256 amount);

    //借贷池创建
    function createPool(
        uint256 _settleTime,
        uint256 _endTime,
        uint256 _interestRate,
        uint256 _maxSupply,
        uint256 _mortgageRate,
        address _lendToken,
        address _borrowToken,
        address _spCoin,
        address _jpCoin,
        uint256 _autoLiquidateThreshold
    ) public validCall {
        // 检查是否已设置token ...
        // 需要结束时间大于结算时间
        require(_endTime > _settleTime, "createPool:end time grate than settle time");
        // 需要_jpToken不是零地址
        require(_spCoin != address(0), "createPool:is zero address");
        // 需要_spToken不是零地址
        require(_jpCoin != address(0), "createPool:is zero address");
        PoolBaseInfo memory poolBaseInfo = PoolBaseInfo({
            settleTime: _settleTime,
            endTime: _endTime,
            interestRate: _interestRate,
            maxSupply: _maxSupply,
            lendSupply: 0,
            borrowSupply: 0,
            mortgageRate: _mortgageRate,
            lendToken: _lendToken,
            borrowToken: _borrowToken,
            state: PoolState.MATCH,
            spCoin: DebtToken(_spCoin),
            jpCoin: DebtToken(_jpCoin),
            autoLiquidateThreshold: _autoLiquidateThreshold
        });
        poolBaseInfos.push(poolBaseInfo);
        poolDataInfos.push(PoolDataInfo(0, 0, 0, 0, 0, 0));
    }

    //存款操作
    function depositLend(uint256 _poolIndex,uint256 _amount) external payable nonReentrant notPaused timeBefore(_poolIndex) stateMatch(_poolIndex) {
        //根据用户传进来的信息，修改对应的池状态
        //因为要修改操作，所以使用storage
        PoolBaseInfo storage poolBaseInfo = poolBaseInfos[_poolIndex];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_poolIndex];
        bool permission = tokeTransferPermission(poolBaseInfo.lendToken, _amount);
        require(permission, "depositLend:approve failed");
        //确保池子的限额是够的
        require(poolBaseInfo.lendSupply + _amount <= poolBaseInfo.maxSupply, "depositLend:exceed max supply");
        //确保用户的存款金额是够的 
        require(msg.value == _amount, "depositLend:msg.value is not equal amount");
        //确保用户的存款金额是大于最小限额
        require(_amount > minAmount, "depositLend:amount is more than min amount");
        //先转账，再变更池信息和用户信息
        uint256 amount = getPayableAmount(poolBaseInfo.lendToken, _amount);
        //保存用户存款信息
        lendInfo.hasNoClaim = false;
        lendInfo.hasNoRefund = false;
        //判断用户存储的代币种类是否为原生代币
        if (poolBaseInfo.lendToken == address(0)) {
            //转账//msg.value不为空，不需要显式调用payable方法，会直接转账的
            poolBaseInfo.lendSupply += msg.value;
            lendInfo.stakeAmount += msg.value;
        }else {
            //如果不是原生代币，就需要调用代币合约的转账方法
            lendInfo.stakeAmount += _amount;
            poolBaseInfo.lendSupply += _amount;
        }
        emit DepositLend(msg.sender, poolBaseInfo.lendToken, amount);
        
    }

    //退还过量存款，根据总借出量进行计算，没有使用的部分推给用户
    function refundLend(uint256 _poolIndex) external nonReentrant notPaused timeAfter(_poolIndex) stateNotMatchUndone(_poolIndex) {
        PoolBaseInfo storage poolBaseInfo = poolBaseInfos[_poolIndex];
        PoolDataInfo storage poolDataInfo = poolDataInfos[_poolIndex];
        LendInfo storage lendInfo = userLendInfo[msg.sender][_poolIndex];
        require(lendInfo.stakeAmount > 0, "refundLend:stake amount is zero");
        require(poolBaseInfo.lendSupply-poolDataInfo.settleAmountLend > 0, "refundLend:pool lend supply is zero");


    }

    //结算操作
    function settle(uint256 _pid) public validCall timeAfter(_pid) stateMatch(_pid) {
        PoolBaseInfo storage pool = poolBaseInfos[_pid];
        PoolDataInfo storage data = poolDataInfos[_pid];
        if(pool.lendSupply >0 && pool.borrowSupply >0){
            uint256[2] memory prices = 
        }
        
    }
    function getTokenPrice(uint _pid) internal returns (uint256[]) {
        PoolBaseInfo memory pool = poolBaseInfos[_pid];
        address[] memory tokens = new address[](2);
        tokens[0] = pool.lendToken;
        tokens[1] = pool.borrowToken;
        return oracle.getPrice(tokens);
    }

    modifier notPaused() {
        require(globalPaused == false, "Pausable: paused");
        _;
    }
    modifier timeBefore(uint256 _pid) {
        require(block.timestamp < poolBaseInfos[_pid].settleTime, "timeBefore: time is over");
        _;
    }
    modifier timeAfter(uint256 _pid) {
        require(block.timestamp > poolBaseInfos[_pid].settleTime, "timeAfter: tx is too early");
        _;
    }
    modifier stateMatch(uint256 _pid) {
        require(poolBaseInfos[_pid].state == PoolState.MATCH, "stateMatch: state is not match");
        _;
    }
    modifier stateNotMatchUndone(uint256 _pid) {
        require(poolBaseInfos[_pid].state == PoolState.EXECUTION || poolBaseInfos[_pid].state == PoolState.FINISH || poolBaseInfos[_pid].state == PoolState.LIQUIDATION,"state: not match and undone");
        _;
    }
    function tokeTransferPermission(address lendToken,uint256 amount) internal returns (bool) {
       return IERC20(lendToken).approve(address(this), amount);
    }

    //转账方法，返回值是转账金额
    function getPayableAmount(address token, uint256 amount) internal returns (uint256) {
        //如果是原生代币，直接返回
        if (token == address(0)) {
            return amount;
        }
        //如果不是原生代币，就需要调用代币合约的转账方法
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        return amount;
    }
    
}