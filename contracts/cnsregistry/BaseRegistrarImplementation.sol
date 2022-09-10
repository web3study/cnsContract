// SPDX-License-Identifier: UNLICCNSED

pragma solidity ^0.8.4;

import "../registry/CNS.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./BaseRegistrar.sol";

contract BaseRegistrarImplementation is ERC721Enumerable, BaseRegistrar {
    // A map of expiry times
    mapping(uint256=>uint) expiries;

    string public baseURI;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private ERC721_ID = bytes4(
        keccak256("totalSupply()") ^
        keccak256("balanceOf(address)") ^
        keccak256("ownerOf(uint256)") ^
        keccak256("approve(address,uint256)") ^
        keccak256("getApproved(uint256)") ^
        keccak256("setApprovalForAll(address,bool)") ^
        keccak256("isApprovedForAll(address,address)") ^
        keccak256("transferFrom(address,address,uint256)") ^
        keccak256("safeTransferFrom(address,address,uint256)") ^
        keccak256("safeTransferFrom(address,address,uint256,bytes)") ^
        keccak256("tokenByIndex(uint256 index)") ^
        keccak256("tokenOfOwnerByIndex(address owner, uint256 index)")
    );
    bytes4 constant private RECLAIM_ID = bytes4(keccak256("reclaim(uint256,address)"));

    constructor(CNS _cns, bytes32 _baseNode) ERC721("Conflux Name Service","CNS") {
        cns = _cns;
        baseNode = _baseNode;
    }

    modifier live {
        require(cns.owner(baseNode) == address(this),"BaseNode not cns owner");
        _;
    }

    modifier onlyController {
        require(controllers[msg.sender],"Controllers error");
        _;
    }
    

    /**
     * @dev Gets the owner of the specified token ID. Names become unowned
     *      when their registration expires.
     * @param tokenId uint256 ID of the token to query the owner of
     * @return address currently marked as the owner of the given token ID
     */
    function ownerOf(uint256 tokenId) public view override(IERC721, ERC721) returns (address) {
        require(expiries[tokenId] > block.timestamp);
        return super.ownerOf(tokenId);
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _base) public onlyOwner{
        baseURI = _base;
    }

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external override onlyOwner {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    // Revoke controller permission for an address.
    function removeController(address controller) external override onlyOwner {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external override onlyOwner {
        cns.setResolver(baseNode, resolver);
    }

    // Returns the expiration timestamp of the specified id.
    function nameExpires(uint256 id) external view override returns(uint) {
        return expiries[id];
    }

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) public view override returns(bool) {
        // Not available if it's registered here or in its grace period.
        return expiries[id] + GRACE_PERIOD < block.timestamp;
    }

    /**
     * @dev Register a name.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function register(uint256 id, address owner, uint duration) external override returns(uint) {
      return _register(id, owner, duration, true);
    }

    /**
     * @dev Register a name, without modifying the registry.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function registerOnly(uint256 id, address owner, uint duration) external returns(uint) {
      return _register(id, owner, duration, false);
    }

    function _register(uint256 tokenId, address owner, uint duration, bool updateRegistry) internal live onlyController returns(uint) {
        require(available(tokenId));
        require(block.timestamp + duration + GRACE_PERIOD > block.timestamp + GRACE_PERIOD,"Time error"); // Prevent future overflow
        expiries[tokenId] = block.timestamp + duration;
        if(_exists(tokenId)) {
            // Name was previously owned, and expired
            _burn(tokenId);
        }
        _mint(owner, tokenId);
        if(updateRegistry) {
            cns.setSubnodeOwner(baseNode, bytes32(tokenId), owner);
        }

        emit NameRegistered(tokenId, owner, block.timestamp + duration);

        return block.timestamp + duration;
    }

    function renew(uint256 id, uint duration) external override live onlyController returns(uint) {
        require(expiries[id] + GRACE_PERIOD >= block.timestamp); // Name must be registered here or in grace period
        require(expiries[id] + duration + GRACE_PERIOD > duration + GRACE_PERIOD); // Prevent future overflow

        expiries[id] += duration;
        emit NameRenewed(id, expiries[id]);
        return expiries[id];
    }

    /**
     * @dev Reclaim ownership of a name in CNS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external override live {
        require(_isApprovedOrOwner(msg.sender, id));
        cns.setSubnodeOwner(baseNode, bytes32(id), owner);
    }

}
