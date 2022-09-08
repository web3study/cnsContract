// SPDX-License-Identifier: UNLICCNSED
pragma solidity ^0.8.0;

import "./CNS.sol";

abstract contract DefaultResolver {
    function setName(bytes32 node, string memory name) public virtual;
}


contract ReverseRegistrar {
    // namehash('addr.reverse')
    bytes32 public constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    CNS public ens;
    DefaultResolver public defaultResolver;

    /**
     * @dev Constructor
     * @param ensAddr The address of the CNS registry.
     * @param resolverAddr The address of the default reverse resolver.
     */
    constructor(CNS ensAddr, DefaultResolver resolverAddr) {
        ens = ensAddr;
        defaultResolver = resolverAddr;

        // Assign ownership of the reverse record to our deployer
        ReverseRegistrar oldRegistrar = ReverseRegistrar(ens.owner(ADDR_REVERSE_NODE));
        if (address(oldRegistrar) != address(0x0)) {
            oldRegistrar.claim(msg.sender);
        }
    }

    /**
     * @dev Transfers ownership of the reverse CNS record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in CNS.
     * @return The CNS node hash of the reverse record.
     */
    function claim(address owner) public returns (bytes32) {
        return claimWithResolver(owner, address(0x0));
    }

    /**
     * @dev Transfers ownership of the reverse CNS record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in CNS.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The CNS node hash of the reverse record.
     */
    function claimWithResolver(address owner, address resolver) public returns (bytes32) {
        bytes32 label = sha3HexAddress(msg.sender);
        bytes32 _node = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, label));
        address currentOwner = ens.owner(_node);

        // Update the resolver if required
        if (resolver != address(0x0) && resolver != ens.resolver(_node)) {
            // Transfer the name to us first if it's not already
            if (currentOwner != address(this)) {
                ens.setSubnodeOwner(ADDR_REVERSE_NODE, label, address(this));
                currentOwner = address(this);
            }
            ens.setResolver(_node, resolver);
        }

        // Update the owner if required
        if (currentOwner != owner) {
            ens.setSubnodeOwner(ADDR_REVERSE_NODE, label, owner);
        }

        return _node;
    }

    /**
     * @dev Sets the `name()` record for the reverse CNS record associated with
     * the calling account. First updates the resolver to the default reverse
     * resolver if necessary.
     * @param _name The name to set for this address.
     * @return The CNS node hash of the reverse record.
     */
    function setName(string memory _name) public returns (bytes32) {
        bytes32 _node = claimWithResolver(address(this), address(defaultResolver));
        defaultResolver.setName(_node, _name);
        return _node;
    }

    /**
     * @dev Returns the node hash for a given account's reverse records.
     * @param addr The address to hash
     * @return The CNS node hash.
     */
    function node(address addr) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr)));
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Ethereum address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
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
