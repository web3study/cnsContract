// SPDX-License-Identifier: UNLICCNSED

pragma solidity ^0.8.0;

import "./PriceOracle.sol";
import "./BaseRegistrar.sol";
import "./StringUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../resolvers/Resolver.sol";

/**
 * @dev A registrar controller for registering and renewing names at fixed cost.
 */
contract CNSRegistrarController is Ownable {
    using StringUtils for *;

    uint constant public MIN_REGISTRATION_DURATION = 28 days;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256,address)") ^
        keccak256("available(string)") ^
        keccak256("makeCommitment(string,address,bytes32)") ^
        keccak256("commit(bytes32)") ^
        keccak256("register(string,address,uint256,bytes32)") ^
        keccak256("renew(string,uint256)")
    );

    bytes4 constant private COMMITMENT_WITH_CONFIG_CONTROLLER_ID = bytes4(
        keccak256("registerWithConfig(string,address,uint256,bytes32,address,address)") ^
        keccak256("makeCommitmentWithConfig(string,address,bytes32,address,address)")
    );

    BaseRegistrar base;
    PriceOracle prices;
    uint public minCommitmentAge;
    uint public maxCommitmentAge;
    uint public minNameLength;
    address public adminAddress;

    mapping(bytes32=>uint) public commitments;
    mapping(address=>address) public dealerAddress;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires,address _dealer);
    event NameRenewed(address indexed operator ,string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, PriceOracle _prices,address _admin) {
        base = _base;
        prices = _prices;
        adminAddress = _admin;
        minCommitmentAge = 60;
        maxCommitmentAge = 86400;
        minNameLength = 2;
    }

    function rentPrice(string memory name, uint duration,address dealer) view public returns(uint) {
        bytes32 hash = keccak256(bytes(name));
        return prices.price(name, base.nameExpires(uint256(hash)), duration,dealer);
    }

    function validMin(string memory name) public view returns(bool) {
        return name.strlen() > minNameLength;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return validMin(name) && base.available(uint256(label));
    }
    
    function makeCommitment(string memory name, address owner, bytes32 secret) pure public returns(bytes32) {
        return makeCommitmentWithConfig(name, owner, secret, address(0), address(0));
    }

    function makeCommitmentWithConfig(string memory name, address owner, bytes32 secret, address resolver, address addr) pure public returns(bytes32) {
        bytes32 label = keccak256(bytes(name));
        if (resolver == address(0) && addr == address(0)) {
            return keccak256(abi.encodePacked(label, owner, secret));
        }
        require(resolver != address(0), "CNSRegistrarController: reovler zero");
        return keccak256(abi.encodePacked(label, owner, resolver, addr, secret));
    }

    function commit(bytes32 commitment) public {
        require(commitments[commitment] + maxCommitmentAge < block.timestamp, "CNSRegistrarController: time error");
        commitments[commitment] = block.timestamp;
    }

    // bytes32 secret
    function register(string calldata name, address owner, uint duration) external payable {
      registerWithConfig(name, owner, duration, address(0), address(0),address(0));
    }

    // bytes32 secret,
    function registerWithConfig(string memory name, address owner, uint duration,  address resolver, address addr , address dealer) public payable {
        require(available(name), "CNSRegistrarController: name error");        
        // bytes32 commitment = makeCommitmentWithConfig(name, owner, secret, resolver, addr);
        uint cost = _consumeCommitment(name,duration,dealer);

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        uint expires;
        if(resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            expires = base.register(tokenId, address(this), duration);

            // The nodehash of this label
            bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

            // Set the resolver
            base.cns().setResolver(nodehash, resolver);

            // Configure the resolver
            if (addr != address(0)) {
                Resolver(resolver).setAddr(nodehash, addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(tokenId, owner);
            base.transferFrom(address(this), owner, tokenId);
        } else {
            require(addr == address(0), "CNSRegistrarController: addr zero");
            expires = base.register(tokenId, owner, duration);
        }

        emit NameRegistered(name, label, owner, cost, expires,dealer);

        // 分销商 指定地址  默认留着当前合约
        if(dealer != address(0) && dealerAddress[dealer] != address(0)){
            payable(dealerAddress[dealer]).transfer(msg.value);
        }else{
            payable(adminAddress).transfer(msg.value);
        }
    }

    function renew(string calldata name, uint duration,address dealer) external payable {
        uint cost = rentPrice(name, duration,dealer);
        require(msg.value >= cost && msg.value > 0, "CNSRegistrarController: price error");

        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);
        
        payable(adminAddress).transfer(msg.value);

        emit NameRenewed(msg.sender,name, label, cost, expires);
    }

    function setPriceOracle(PriceOracle _prices) public onlyOwner {
        prices = _prices;
        emit NewPriceOracle(address(prices));
    }
    
    function setAdmin(address _admin) public onlyOwner {
        require(_admin != address(0), "CNSRegistrarController: admin zero");
        adminAddress = _admin;
    }

    function setCommitmentAges(uint _minCommitmentAge, uint _maxCommitmentAge) public onlyOwner {
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function setNameLength(uint _minNameLength) public onlyOwner {
        minNameLength = _minNameLength;
    }

    function setDealerAddress(address _dealerAddress,address _payAddress) public onlyOwner {
        dealerAddress[_dealerAddress] = _payAddress;
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID ||
               interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID;
    }

    function _consumeCommitment(string memory name, uint duration,address dealer) internal returns (uint256) {
        // Require a valid commitment
        // require(commitments[commitment] + minCommitmentAge <= block.timestamp);

        // // If the commitment is too old, or the name is registered, stop
        // require(commitments[commitment] + maxCommitmentAge > block.timestamp);
        // require(available(name));

        // delete(commitments[commitment]);

        uint cost = rentPrice(name, duration,dealer);
        require(duration >= MIN_REGISTRATION_DURATION, "CNSRegistrarController: duration error");
        require(msg.value >= cost, "CNSRegistrarController: cost error");

        return cost;
    }

}
