// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

//首先说明为什么要使用mulitSignatureClient.sol这个合约
//在多签合约中，我们需要通过读取合约的signatureMap来获取某个交易者是否已经得到授权许可，但是在业务逻辑中我们是无法直接获取多签的地址的，
//所以我们需要一个中间合约来帮助我们获取多签的地址，并调用合约的方法去查询signatureMap
//使用sstore可以将合约地址存放到区块的存储槽中，这样我们就可以通过sload来获取多签合约的地址，去调用其方法
interface IMultiSignature {
    function checkSignatureNumber(bytes32 key) external view returns(bool);
    
}
contract multiSignatureClient {
    uint private constant multiSignaturePostion = uint256(keccak256("org.multiSignature.storage"));

    constructor(address multiSignatureAddress) {
        require(multiSignatureAddress != address(0), "multiSignatureAddress is zero");
        saveAddress(multiSignaturePostion, uint160(multiSignatureAddress));
    }

    function saveAddress(uint256 position,uint256 value) internal {
        assembly {
            sstore(position, value)
        }
    }
    function getAddress(uint256 position) internal view returns(address) {
        uint256 value;
        assembly {
            value := sload(position)
        }
        return address(uint160(value));
    }

    //在这里定义modifier方法，用来进行多签认证
    modifier validCall {
        checkMultiSignature();
        _;
    }
    function checkMultiSignature() internal view {
        //使用signatureMap的key去找到对应的signatureInfo
        bytes32 key = keccak256(abi.encodePacked(msg.sender,address(this)));
        address multiSignatureAddress = getAddress(multiSignaturePostion);

        bool signSuccess = IMultiSignature(multiSignatureAddress).checkSignatureNumber(key);

        require(signSuccess, "signature failed");


    }
}