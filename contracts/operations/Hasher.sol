// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "./AlligatorPair.sol";

contract Hasher {
    function getInitHash() public pure returns (bytes32) {
        bytes memory bytecode = type(AlligatorPair).creationCode;
        return keccak256(abi.encodePacked(bytecode));
    }
}
