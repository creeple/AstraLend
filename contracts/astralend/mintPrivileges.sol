// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../multiSignature/multiSignatureClient.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

//这个合约是用来控制谁可以进行铸币操作的
contract mintPrivileges is multiSignatureClient{
    //如果父合约的构造函数传参了，那么子合约的构造函数也要传参
    constructor(address multiSignatureAddress) multiSignatureClient(multiSignatureAddress) {
    }

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;

    //添加铸币者
    function addMinter(address minter) public validCall returns (bool) {
        require(minter != address(0), "mintPrivileges: minter is the zero address");
        return _minters.add(minter);
        //不推荐使用EnumerableSet.add(_minters, minter);
    }
    //删除铸币者
    function delMinter(address minter) public validCall returns (bool) {
        require(minter != address(0), "mintPrivileges: minter is the zero address");
        return _minters.remove(minter);
    }
    //查询是否为铸币者
    function isMinter(address minter) public view returns (bool) {
        return _minters.contains(minter);
    }
    modifier onlyMinter() {
        require(isMinter(msg.sender), "mintPrivileges: caller is not the minter");
        _;
    }
}