// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// Chainlink Imports
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// This import includes functions from both ./KeeperBase.sol and
// ./interfaces/KeeperCompatibleInterface.sol
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
// VRF for random numbers
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";


// Dev imports
// import "hardhat/console.sol";

contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, KeeperCompatibleInterface, VRFConsumerBaseV2 {
    
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;
    AggregatorV3Interface public priceFeed;

    // exposing index for debug
    uint256 public uriIndex;

    // VRF RandomNumber ==================================================================
    VRFCoordinatorV2Interface /*public*/ COORDINATOR;
    // Your subscription ID.
    // TODO: Replace ID by environment variable
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
    bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint32 callbackGasLimit = 600000;
    uint16 requestConfirmations = 3;
    uint32 numWords =  1;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    // ====================================================================================

    uint256 public /*immutable*/ interval;
    uint256 public lastTimeStamp;

    int256 public currentPrice;

    string public currentTrend = "BULL"; 

    // IPFS URIs for the dynamic nft graphics/metadata.
    // NOTE: These connect to my IPFS Companion node.
    // You should upload the contents of the /ipfs folder to your own node for development.
    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    event TokensUpdated(string Trend);

    constructor(uint256 updateInterval, uint64 vrfSubscriptionId, address _priceFeed, address vrfCoordinator) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(vrfCoordinator) {
        // Sets the keeper update interval
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        // set the price feed address to
        // BTC/USD Price Feed Contract Address on Rinkeby: https://rinkeby.etherscan.io/address/0xECe365B379E1dD183B20fc5f022230C044d51404
        // or the MockPriceFeed Contrac
        priceFeed = AggregatorV3Interface(_priceFeed);
        
        // set the price for the chosen currency pair.
        currentPrice = getLatestPrice();

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);

        // pass the subscriptionId argument (to avoid using env or hardcode Id) to s_subscriptionId
        s_subscriptionId = vrfSubscriptionId;
    }

    function safeMint(address to) public onlyOwner {
        // Current counter value will be the minted token's token ID.
        uint256 tokenId = _tokenIdCounter.current();

        // Increment it so next time it's correct when we call .current()
        _tokenIdCounter.increment();

        // Mint the token
        _safeMint(to, tokenId);

        // Default to a bull NFT
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);
    }


    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory /*performData */) {
         upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }


    function performUpkeep(bytes calldata /* performData */ ) external override {
        //We highly recommend revalidating the upkeep in the performUpkeep function
        if ((block.timestamp - lastTimeStamp) > interval ) {
            lastTimeStamp = block.timestamp;         
            int latestPrice =  getLatestPrice(); 
       
            if (latestPrice == currentPrice) {
                // console.log("NO CHANGE -> returning!");
                return;
            }
            if (latestPrice < currentPrice) {
                // bear
                // console.log("ITS BEAR TIME");
                currentTrend = "BEAR";
                // updateAllTokenUris("bear");
            } else {
                // bull
                // console.log("ITS BULL TIME");
                currentTrend = "BULL";
                // updateAllTokenUris("bull");
            }

            // Initiate the VRF calls to get a random number (word)
            // that will then be used to to choose one of the URIs 
            // that gets applied to all minted tokens.
            requestRandomWords();

            // update currentPrice
            currentPrice = latestPrice;
        } else {
            // console.log("INTERVAL NOT UP!");
            return;
        }
    }


    function getLatestPrice() public view returns (int256) {
         (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();

        return price; //  example price returned 3034715771688
    }


    function updateAllTokenUris(string memory currentTrend, uint256 uriIndex) internal {
        if (compareStrings("BEAR", currentTrend)) {
            // console.log(" UPDATING TOKEN URIS WITH ", "BEAR", currentTrend);
            for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
                _setTokenURI(i, bearUrisIpfs[uriIndex]);
            } 
            
        } else {     
            // console.log(" UPDATING TOKEN URIS WITH ", "BULL", currentTrend);

            for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
                _setTokenURI(i, bullUrisIpfs[uriIndex]);
            }  
        }   
        emit TokensUpdated(currentTrend);
    }

    
    function setPriceFeed(address newFeed) public onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
    }


    // Helpers

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }

    // VRF Functions START ================================================
    function requestRandomWords() internal {
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
        keyHash,
        s_subscriptionId,
        requestConfirmations,
        callbackGasLimit,
        numWords
        );
    }
    
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;
        uint256 uriArrayLength = 0;
        // Obtain the module between randomword and URI array length
        // change bullUrisIpfs.length for URI trend length
        if (compareStrings("BULL", currentTrend)) {
            uriArrayLength = bullUrisIpfs.length;
        } else {
            uriArrayLength = bearUrisIpfs.length;
        }
        
        // use module to obtain a number between 0 and uriArrayLength
        uriIndex = randomWords[0] % uriArrayLength;
        // call function to update all Uris according to Trend
        updateAllTokenUris(currentTrend, uriIndex);

    }
    // VRF Functions END ================================================


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
