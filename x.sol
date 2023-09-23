pragma solidity >=0.8.2 <0.9.0;

import {IXSquared} from "./interfaces/IXSquared.sol";

/*
| ---------------------------------XSQUARED----------------------------------*----
|                                                                           *   
|                                                                         *     
|                                                                               
|                                                                       *       
|                                                                               
|                                                                     *         
|                                                                               
|                                                                   *           
|                                                                               
|                                                                 *             
|                                                                               
|                                                               *               
|                                                             *                 
|                                                                               
|                                                           *                   
|                                                         *                     
|                                                                               
|                                                       *                       
|                                                     -                         
|                                                                               
|                                                   -                           
|                                                 -                             
|                                               -                               
|                                                                               
|                                             -                                 
|                                           -                                   
|                                         -                                     
|                                       -                                       
|                                     -                                         
|                                   -                                           
|                                 -                                             
|                               -                                               
|                           - -                                                 
|                         -                                                     
|                     - -                                                       
|                 - -                                                           
|             - -                                                               
| - - - - - -                                                                   
--------------------------------------------------------------------------------

## Introduction

XSquared is a protocol for creating and trading royalty-enforcing digital collectibles using bonding curve along the x^2 curve.

XSquared is a decentralized public good. There is no owner, no fee, no governance, and no upgradable functions. There is no website and no Twitter. This contract is the only documentation.

## Models

Items are created within a Collection. Items can be bought and sold. A configurable fee is given to both the Collection-creator and the Item-creator. 

Items have infinite supply and are bought and sold along the x^2 curve. The curve is configured at Collection creation and cannot be changed.

## Collections API

To create a Collection, use `createCollection` on the `XSquaredFactory` which will use CREATE2 to deploy a new contract.

The bonding curve can be configured by using the denominator settings `slopeScale` and `slopeMagnitude`. For example, slopeScale of 4 and slopeMagnitude of 4 will create the curve: x^2 / (4 * 1_0000).

The `feeSetter` address can update the collection fee, the item creator fee, the fee destination, the item creator address, and the `feeSetter` address itself. The bonding curve parameters are not upgradable.

## Buying and Selling API

Items are bought and sold using `buyItem` and `sellItem`. 

The price is calculated using the bonding curve. The price is paid in ETH and the fees are sent to the Collection creator and the Item creator, the remaining ETH is stored within the contract and cannot be withdrawn apart from selling. 

There are no emergency withdrawal functions.

## Items API

Items are identified by a `bytes32`. The protocol is agnostic to what these items are. It provides two fields to store on-chain metadata: 

* `string text`
* `bytes data`

Use these fields as you wish. 

Create an item with: `createItem(bytes32 item, address to, address feeDestination, string calldata text, bytes calldata data)`.

The `feeDestination` for items can be updated by the current `feeDestination` address.

## Events

The following events are emitted:

* Trade
* ItemCreated
* CollectionCreated
* CollectionSettings
* ItemSettings

## Building on XSquared

- Create a Collection by calling `createCollection` on XSquaredFactory
- Create Items with `createItem`
- Buy the Item with `buyItem`
- Sell the Item with `sellItem`

Convenience functions for getting prices are provided. 

*/

contract XSquared is IXSquared {
    Collection public _collection;

    mapping(bytes32 => Item) public _items;

    mapping(bytes32 => mapping(address => uint256)) public balanceOf;

    /// @notice Initialize a new collection
    /// @dev slopeScale and slopeMagnitude define the curve. For example,
    /// slopeScale of 4 and slopeMagnitude of 4 will create the curve: x^2 / (4 * 1_0000)
    /// @param id the collection id e.g. keccak256('MYCOLLECTIONUWU')
    /// @param collectionFee the collection fee percent in bips (max 1000 = 10%)
    /// @param itemFee the item fee percent in bips (max 1000 = 10%)
    /// @param owner the address that can change collection settings
    /// @param feeDestination the address that receives collection fees
    /// @param allowedItemCreator the address that is allowed to create items
    /// @param slopeScale the scale of the x^2 curve denominator slope (power of two lte 1024)
    /// @param slopeMagnitude the magnitude of the x^2 curve denominator slope (number of zeros, 4 = 10000)
    function initialize(
        bytes32 id,
        uint256 collectionFee,
        uint256 itemFee,
        address owner,
        address feeDestination,
        address allowedItemCreator,
        uint256 slopeScale,
        uint256 slopeMagnitude
    ) public {
        require(_collection.id == 0, "ALREADY_INITIALIZED");

        _collection.id = id;
        _updateCollection(collectionFee, itemFee, owner, feeDestination, allowedItemCreator, slopeScale, slopeMagnitude);
    }

    function updateCollection(
        uint256 collectionFee,
        uint256 itemFee,
        address owner,
        address feeDestination,
        address allowedItemCreator
    ) public {
        require(_collection.owner == msg.sender, "UNAUTHORIZED_ONLY_COLLECTION_OWNER");

        require(_collection.slopeScale != 0, "COLLECTION_NOT_CREATED");

        _updateCollection(
            collectionFee,
            itemFee,
            owner,
            feeDestination,
            allowedItemCreator,
            _collection.slopeScale, // not changeable
            _collection.slopeMagnitude // not changeable
        );
    }

    function _updateCollection(
        uint256 collectionFee,
        uint256 itemFee,
        address owner,
        address feeDestination,
        address allowedItemCreator,
        uint256 slopeScale,
        uint256 slopeMagnitude
    ) private {
        require(collectionFee <= 1000, "COLLECTION_FEE_TOO_HIGH"); // max 10%
        require(itemFee <= 1000, "ITEM_FEE_TOO_HIGH"); // max 10%
        require(isPowerOfTwo(slopeScale), "SLOPE_NOT_POWER_OF_TWO");
        require(slopeMagnitude >= 1 && slopeMagnitude < 10, "SLOPE_MAGNITUDE");

        _collection.collectionFee = collectionFee;
        _collection.itemFee = itemFee;
        _collection.owner = owner;
        _collection.feeDestination = feeDestination;
        _collection.allowedItemCreator = allowedItemCreator;
        _collection.slopeScale = slopeScale;
        _collection.slopeMagnitude = slopeMagnitude;

        emit CollectionSettings(_collection.id, collectionFee, itemFee, owner, feeDestination, allowedItemCreator);
    }

    function createItem(bytes32 item, address to, address feeDestination, string calldata text, bytes calldata data)
        public
        payable
    {
        require(_collection.slopeScale != 0, "COLLECTION_NOT_CREATED");
        require(
            _collection.allowedItemCreator == address(0) /* public creation */
                || _collection.allowedItemCreator == msg.sender,
            "UNAUTHORIZED_ONLY_ALLOWED_ITEM_CREATOR"
        );

        uint256 supply = _items[item].supply;
        require(supply == 0, "ITEM_ALREADY_CREATED");

        _items[item].data = data;
        _items[item].feeDestination = feeDestination;
        _items[item].text = text;

        emit ItemCreated(_collection.id, item, to, text, data);
        emit ItemSettings(_collection.id, item, feeDestination);

        _buyItem(item, to, supply, 1); // buy the first item to actual creator
    }

    function updateItem(bytes32 item, address feeDestination) public {
        require(_items[item].supply > 0, "ITEM_NOT_CREATED");
        require(_items[item].feeDestination == msg.sender, "UNAUTHORIZED_ONLY_PRIOR_FEE_DESTINATION");

        _items[item].feeDestination = feeDestination;

        emit ItemSettings(_collection.id, item, feeDestination);
    }

    function buyItem(bytes32 item, uint256 amount) public payable {
        uint256 supply = _items[item].supply;
        require(supply > 0, "ITEM_NOT_CREATED");

        _buyItem(item, msg.sender, supply, amount);
    }

    function _buyItem(bytes32 item, address to, uint256 supply, uint256 amount) internal {
        uint256 price = getPrice(supply, amount);
        uint256 collectionFee = getCollectionFee(price);
        uint256 itemFee = getItemFee(price);
        uint256 totalRequired = price + collectionFee + itemFee;

        require(msg.value >= totalRequired, "INSUFFICIENT_PAYMENT");

        balanceOf[item][to] = balanceOf[item][to] + amount;
        _items[item].supply = supply + amount;

        address collectionFeeDestination = _collection.feeDestination;
        address itemFeeDestination = _items[item].feeDestination;

        emit Trade(
            _collection.id,
            item,
            to,
            true,
            amount,
            supply + amount,
            price,
            collectionFeeDestination,
            collectionFee,
            itemFeeDestination,
            itemFee
        );

        collectionFeeDestination.call{value: collectionFee}("");
        itemFeeDestination.call{value: itemFee}("");

        uint256 excess = msg.value - totalRequired;

        if (excess > 0) {
            msg.sender.call{value: excess}("");
        }
    }

    function sellItem(bytes32 item, uint256 amount) public payable {
        uint256 supply = _items[item].supply;
        require(supply > amount, "CANNOT_SELL_LAST_ITEM");

        uint256 price = getPrice(supply - amount, amount);
        uint256 collectionFee = getCollectionFee(price);
        uint256 itemFee = getItemFee(price);
        require(balanceOf[item][msg.sender] >= amount, "INSUFFICIENT_HOLDINGS");

        balanceOf[item][msg.sender] = balanceOf[item][msg.sender] - amount;
        _items[item].supply = supply - amount;

        address collectionFeeDestination = _collection.feeDestination;
        address itemFeeDestination = _items[item].feeDestination;

        emit Trade(
            _collection.id,
            item,
            msg.sender,
            false,
            amount,
            supply - amount,
            price,
            collectionFeeDestination,
            collectionFee,
            itemFeeDestination,
            itemFee
        );

        collectionFeeDestination.call{value: collectionFee}("");
        itemFeeDestination.call{value: itemFee}("");

        msg.sender.call{value: price - collectionFee - itemFee}("");
    }

    function getPrice(uint256 supply, uint256 amount) public view returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        uint256 price = (summation * 1 ether) / (_collection.slopeScale * powerOfTen(_collection.slopeMagnitude));
        require(price < type(uint128).max, "PRICE_OVERFLOW"); // don't fly too close to the sun
        return price;
    }

    function getBuyPrice(bytes32 item, uint256 amount) public view returns (uint256) {
        return getPrice(_items[item].supply, amount);
    }

    function getSellPrice(bytes32 item, uint256 amount) public view returns (uint256) {
        return getPrice(_items[item].supply - amount, amount);
    }

    function getBuyPriceAfterFee(bytes32 item, uint256 amount) external view returns (uint256) {
        uint256 price = getBuyPrice(item, amount);
        return price + getCollectionFee(price) + getItemFee(price);
    }

    function getSellPriceAfterFee(bytes32 item, uint256 amount) external view returns (uint256) {
        uint256 price = getSellPrice(item, amount);
        return price - getCollectionFee(price) - getItemFee(price);
    }

    function getCollectionFee(uint256 price) internal view returns (uint256) {
        return (price * _collection.collectionFee) / 10000;
    }

    function getItemFee(uint256 price) internal view returns (uint256) {
        return (price * _collection.itemFee) / 10000;
    }

    function isPowerOfTwo(uint256 n) private pure returns (bool) {
        return (n != 0) && ((n & (n - 1)) == 0) && (n > 1) && (n <= 1024);
    }

    function powerOfTen(uint256 n) private pure returns (uint256) {
        if (n == 1) return 10;
        if (n == 2) return 100;
        if (n == 3) return 1000;
        if (n == 4) return 10000;
        if (n == 5) return 100000;
        if (n == 6) return 1000000;
        if (n == 7) return 10000000;
        if (n == 8) return 100000000;
        if (n == 9) return 1000000000;
        if (n == 10) return 10000000000;
        return 10;
    }

    function collection() external view returns (Collection memory) {
        return _collection;
    }

    function items(bytes32 id) external view returns (Item memory) {
        return _items[id];
    }
}