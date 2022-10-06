// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";


contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, KeeperCompatibleInterface, VRFConsumerBaseV2  {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public priceFeed;

    VRFCoordinatorV2Interface public COORDINATOR;

    uint256[] public vrfRandomWords;
    uint256 public vrfRequestId;
    uint32 public callbackGasLimit = 500000;
    uint64 public vrfSubscriptionId;
    bytes32 keyhash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15; 
    

    uint public interval; 
    uint public lastTimeStamp;
    int256 public currentPrice;
    bool upkeepCondition = (block.timestamp - lastTimeStamp) > interval;

    enum TrendType { BULL, BEAR }
    TrendType public currentTrendType = TrendType.BULL; 
    event TrendChanged(TrendType trend);
    mapping (TrendType => string[]) trendToUris;
    
    string[] bullUris = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];
    string[] bearUris = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    constructor(uint updateInterval, address _priceFeed, address _vrfCoordinator) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(_vrfCoordinator) {
        interval = updateInterval; 
        lastTimeStamp = block.timestamp; 

        priceFeed = AggregatorV3Interface(_priceFeed); 

        currentPrice = getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);  

        trendToUris[TrendType.BULL] = bullUris;
        trendToUris[TrendType.BEAR] = bearUris;
    }

    function safeMint(address to) public  {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _safeMint(to, tokenId);

        string memory defaultUri = trendToUris[TrendType.BULL][0];
        _setTokenURI(tokenId, defaultUri);
    }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory /*performData */) {
         upkeepNeeded = upkeepCondition;
    }

    function performUpkeep(bytes calldata /* performData */ ) external override {
        if (upkeepCondition) {
            lastTimeStamp = block.timestamp;         
            int latestPrice =  getLatestPrice(); 
        
            if (latestPrice == currentPrice) {
                return;
            } else if (latestPrice < currentPrice) {
                currentTrendType = TrendType.BEAR;
            } else {
                currentTrendType = TrendType.BULL;
            }

            requestCreatingNftUriByTrendAndRandom();

            currentPrice = latestPrice;
        } else {
            return;
        }
    }

    function getLatestPrice() public view returns (int256) {
         (,int price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function requestCreatingNftUriByTrendAndRandom() internal {
        require(vrfSubscriptionId != 0, "set subscription ID"); 

        // Will revert if subscription is not set and funded.
        vrfRequestId = COORDINATOR.requestRandomWords(
            keyhash,
            vrfSubscriptionId,
            1, // requestConfirmations
            callbackGasLimit,
            5 // numWords, max 500 for rinkeby
        );
    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        vrfRandomWords = randomWords;

        uint256 uriIndex = (randomWords[0] % (trendToUris[currentTrendType].length)); // index from 0 to last index in URI array of current trend type in the mapping

        for (uint i = 0; i < _tokenIdCounter.current(); i++) {
            _setTokenURI(i, trendToUris[currentTrendType][uriIndex]);
        } 
        
        emit TrendChanged(currentTrendType);
    }


    function setpriceFeed(address newFeed) public onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
    }
    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }

    function setSubscriptionId(uint64 _id) public onlyOwner {
        vrfSubscriptionId = _id;
    }


    function setCallbackGasLimit(uint32 maxGas) public onlyOwner {
        callbackGasLimit = maxGas;
    }

    function setVrfCoodinator(address _address) public onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(_address);
    }



    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}