// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./mintPrivileges.sol";



//这个合约用于控制债务代币的发行
contract DebtToken is ERC20, mintPrivileges {
    constructor(string memory name, string memory symbol, address multiSignatureAddress) ERC20(name, symbol) mintPrivileges(multiSignatureAddress) {
    }
    event mintToken(address minter,address to,uint256 amount);
    event burnToken(address minter,address to,uint256 amount);

    //铸币
    function mint(address account, uint256 amount) public onlyMinter returns (bool) {
        _mint(account, amount);
        emit mintToken(msg.sender,account,amount);
        return true;
    }
    //销毁
    function burn(address account, uint256 amount) public onlyMinter returns (bool) {
        _burn(account, amount);
        emit burnToken(msg.sender,account,amount);
        return true;
    }
}