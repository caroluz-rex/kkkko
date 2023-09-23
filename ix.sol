pragma solidity >=0.8.2 <0.9.0;

interface IXSquared {
    struct Collection {
        bytes32 id;
        uint256 collectionFee; // bips
        uint256 itemFee; // bips
        address owner; // collection owner that can update settings
        address feeDestination; // for collection (item fee destination is set on the items)
        address allowedItemCreator;
        uint256 slopeScale;
        uint256 slopeMagnitude;
    }

    struct Item {
        uint256 supply;
        address feeDestination;
        string text;
        bytes data;
    }

    event Trade(
        bytes32 collection,
        bytes32 item,
        address trader,
        bool isBuy,
        uint256 quantity,
        uint256 supply,
        uint256 ethAmount,
        address collectionFeeDestination,
        uint256 collectionFeeEthAmount,
        address itemFeeDestination,
        uint256 itemFeeEthAmount
    );

    event ItemCreated(bytes32 collection, bytes32 item, address creator, string text, bytes data);

    event CollectionCreated(bytes32 collection, address creator);

    event CollectionSettings(
        bytes32 collection,
        uint256 collectionFeePercent,
        uint256 itemFeePercent,
        address owner,
        address feeDestination,
        address allowedItemCreator
    );
    event ItemSettings(bytes32 collection, bytes32 item, address feeDestination);

    function initialize(
        bytes32 id,
        uint256 collectionFee,
        uint256 itemFee,
        address owner,
        address feeDestination,
        address allowedItemCreator,
        uint256 slopeScale,
        uint256 slopeMagnitude
    ) external;

    function updateCollection(
        uint256 collectionFee,
        uint256 itemFee,
        address owner,
        address feeDestination,
        address allowedItemCreator
    ) external;

    function collection() external view returns (Collection memory);

    function items(bytes32 item) external view returns (Item memory);

    function createItem(bytes32 item, address to, address feeDestination, string calldata text, bytes calldata data)
        external
        payable;

    function updateItem(bytes32 item, address feeDestination) external;

    function buyItem(bytes32 item, uint256 amount) external payable;

    function sellItem(bytes32 item, uint256 amount) external payable;

    function getPrice(uint256 supply, uint256 amount) external view returns (uint256);

    function getBuyPrice(bytes32 item, uint256 amount) external view returns (uint256);

    function getSellPrice(bytes32 item, uint256 amount) external view returns (uint256);

    function getBuyPriceAfterFee(bytes32 item, uint256 amount) external view returns (uint256);

    function getSellPriceAfterFee(bytes32 item, uint256 amount) external view returns (uint256);

    function balanceOf(bytes32 item, address holder) external view returns (uint256);
}