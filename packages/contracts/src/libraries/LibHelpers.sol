// SPDX-License-Identifier: UNKOWN
pragma solidity >=0.8.24;

library LibHelpers {
  function addressToEntity(address a) internal pure returns (bytes32) {
    return bytes32(uint256(uint160((a))));
  }

  function entityToAddress(bytes32 a) internal pure returns (address) {
    return address(uint160(uint256((a))));
  }
}
