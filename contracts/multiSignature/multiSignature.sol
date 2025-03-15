// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./multiSignatureClient.sol";

//规范化白名单地址的操作
library whiteListAddress {
    function addWhiteListAddress(address[] storage whiteList, address temp) internal {
        //首先判断白名单中是否已经存在这个地址
        if (!isExistAddress(whiteList, temp)) {
            whiteList.push(temp);
        }
    }

    function removeWhiteListAddress(address[] storage whiteList, address temp) internal returns (bool){
        uint256 len = whiteList.length;
        uint256 index = 0;
        for (; index < len; index++) {
            if (whiteList[index] == temp)
                break;
        }
        if(index<len){
            if(index !=len-1){
                whiteList[index] = whiteList[len-1];
            }
            whiteList.pop();
            return true;
        }
        return false;
    }

    function isExistAddress(address[] memory whiteList, address temp) internal pure returns (bool) {
        for (uint i = 0; i < whiteList.length; i++) {
            if (whiteList[i] == temp)
                return true;
        }
        return false;
    }
}

contract multiSignature is multiSignatureClient {
    using whiteListAddress for address[];
    //所有管理员的地址
    address[] public signatureOwners;
    //管理员的最小签名数量
    uint256 public minSignatureNum;

    struct signatureInfo {
        address applicant;
        address[] signatureOwner;
    }
    mapping(bytes32 => signatureInfo) public signatureMap;


    //初始化管理员地址和最小签名数量
    //在 0.7.0 版本之后，构造函数不再支持 public、internal、external 和 private 修饰符
    constructor(address[] memory owners, uint256 threshold) multiSignatureClient(address(this)) {
        require(owners.length >= threshold, "signatureOwners length must be greater than _minSignatureNum");
        require(threshold > 0, "threshold must be greater than 0");
        signatureOwners = owners;
        minSignatureNum = threshold;
    }

    //owner转让
    function transferOwner(address newOwner) public onlyOwner validCall{
        require(newOwner != address(0), "newOwner is zero");
        require(!signatureOwners.isExistAddress(newOwner), "newOwner is exist");
        for (uint i = 0; i < signatureOwners.length; i++) {
            if (signatureOwners[i] == msg.sender) {
                signatureOwners[i] = newOwner;
                break;
            }
        }
    }

    //创建签名申请
    function createSignature() external returns (bytes32) {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, address(this)));
        require(signatureMap[key].applicant == address(0), "signature has been created");
        signatureMap[key].applicant = msg.sender;
        signatureMap[key].signatureOwner = new address[](0);
        return key;
    }

    //同意申请
    function agreeSignature(bytes32 key) external onlyOwner{
        require(signatureMap[key].applicant != address(0), "signature does not exist");
        require(!signatureMap[key].signatureOwner.isExistAddress(msg.sender), "signature has been agreed");
        signatureMap[key].signatureOwner.addWhiteListAddress(msg.sender);
    }
    //拒绝申请或者是撤销签名
    function revokeSignature(bytes32 key) external onlyOwner{
        require(signatureMap[key].applicant != address(0), "signature does not exist");
        if(signatureMap[key].signatureOwner.isExistAddress(msg.sender)){
            signatureMap[key].signatureOwner.removeWhiteListAddress(msg.sender);
        }
    }

    //接口方法实现，判断授权人数是否符合要求
    function checkSignatureNumber(bytes32 key) public view returns (bool) {
        if (signatureMap[key].signatureOwner.length >= minSignatureNum) {
            return true;
        }
        return false;
    }

    modifier onlyOwner {
        require(signatureOwners.isExistAddress(msg.sender), "only owner can call");
        _;
    }
    //查询签名申请
    function getSignatureInfo(bytes32 key) public view returns (address, address[] memory) {
        return (signatureMap[key].applicant, signatureMap[key].signatureOwner);
    }
    
}
