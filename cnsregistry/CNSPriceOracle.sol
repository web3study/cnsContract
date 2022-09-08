// SPDX-License-Identifier: UNLICCNSED

pragma solidity ^0.8.4;

import "./PriceOracle.sol";
import "./SafeMath.sol";
import "./StringUtils.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// StablePriceOracle sets a price in USD, based on an oracle.
contract CNSPriceOracle is Ownable, PriceOracle {
    using SafeMath for uint256;
    using StringUtils for *;

    // Rent in base price units by length. Element 0 is for 1-length names, and so on.
    uint[] public rentPrices;

    mapping(address=>uint) public discount;

    event RentPriceChanged(uint[] prices);

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private ORACLE_ID = bytes4(keccak256("price(string,uint256,uint256)") ^ keccak256("premium(string,uint256,uint256)"));

    constructor(uint[] memory _rentPrices) {
        setPrices(_rentPrices);
        discount[address(0)] = 1e18;
    }

    function price(string calldata name, uint expires, uint duration, address dealer) external view override returns(uint) {
        // expires is not used in this contract
        uint len = name.strlen();
        //over price length - 1
        if(len > rentPrices.length) {
            len = rentPrices.length;
        }
        require(len > 0);
        //for about 365.25 4years leap
        uint ys = duration.div(31557600);
        if(duration % 31557600 > 0 ){
             ys += 1;   
        }
        
        uint basePrice = rentPrices[len - 1].mul(ys).mul(discount[dealer] == 0?1e18:discount[dealer]);
        return basePrice.div(1e18);
    }

    /**
     * @dev Sets rent prices.
     * @param _rentPrices The price array. Each element corresponds to a specific
     *                    name length; names longer than the length of the array
     *                    default to the price of the last element. Values are
     *                    in base price units, equal to one attodollar (1e-18
     *                    dollar) each.
     */
    function setPrices(uint[] memory _rentPrices) public onlyOwner {
        rentPrices = _rentPrices;
        emit RentPriceChanged(_rentPrices);
    }

    function setDiscount(address _dealer,uint _discount) public onlyOwner {
        discount[_dealer] = _discount;
    }

    function supportsInterface(bytes4 interfaceID) public view virtual returns (bool) {
        return interfaceID == INTERFACE_META_ID || interfaceID == ORACLE_ID;
    }
}
