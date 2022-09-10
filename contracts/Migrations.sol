// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract Migrations {
  address public owner = msg.sender;
  uint public last_completed_migration;

  modifier restricted() {
    require(
      msg.sender == owner,
      "This function is restricted to the contract's owner"
    );
    _;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }

  function _transfer() external payable{
    payable(msg.sender).transfer(1e16);
    payable(address(this)).transfer(1e16);
  }

  function test21(string calldata name) view external returns(uint256,bytes32,bytes32){
      bytes32 label = keccak256(bytes(name));
      uint256 tokenId = uint256(label);
      bytes32 lable1 = bytes32(tokenId);
      return (tokenId,label,lable1);
  }

  uint256[] public rentPrices;
  mapping(address=>uint256) public asd;

  function setArr(uint duration) pure external returns(uint ys){
    return duration == 0?1:1e18; 
  }

  uint256 public value;

    // bytes32 secret
  function register() external payable returns(uint256) {
  return value = msg.value;
  }

  function testKec(bytes32 node,bytes32 label) view external returns(bytes32){
      return keccak256(abi.encodePacked(node, label));
  }

  function sha3HexAddress(address addr) external pure returns (bytes32 ret) {
        addr;
        ret; // Stop warning us about unused variables
        assembly {
            let lookup := 0x3031323334353637383961626364656600000000000000000000000000000000

            for { let i := 40 } gt(i, 0) { } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }
}
