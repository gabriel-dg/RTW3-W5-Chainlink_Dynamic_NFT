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
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
    bytes32 keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
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
    string[] bullUrisIpfs = [
        "https://gateway.pinata.cloud/ipfs/QmaMaNMGtghc7QMZeqWrjcneBNSW8Q6AmBdhuDoeHXmdEj?filename=bull_01_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmfQceHB9671ePfCTuebskxHS3zR7h6uKHTKLr8bhirtuk?filename=bull_02_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmU5ShFPwXGfzBQT5C4pzwGQRGJwfkgwK6GxRYB1VcWreG?filename=bull_03_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmbAkFrG4jYaRE2ZN8vJ2VtCRjvgD4c9wgR6gdpUFRw1vm?filename=bull_04_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmULJuKFoMGndrVCdqTqUX9DfuL2Zmhk24dNZEDfaVAKyq?filename=bull_05_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmeQjMYNqjGFVzzSpXShQubBeqV3Qdb659BjBi5x4XSout?filename=bull_06_metadata.json"
    ];
    string[] bearUrisIpfs = [
        "https://gateway.pinata.cloud/ipfs/QmejFF6abr97QavriTCVFK8HPzCopi6sc7WXZxPHe3DKLT?filename=bear_01_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmUP9p4AxbN6eRqxUpptuLEULEyoFd4DrtCP2amCLoLvKt?filename=bear_02_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmSAjAHHwevAmfgMrxavfPBuTpVGWVBJsn4kgTyQGTUcWA?filename=bear_03_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmYeW98EsuvyiC1oJWa2tGvPjktdu4fBJPEiQBhkuAr1dC?filename=bear_04_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmYFtFr7sZgd1xnMxk5XUcjVe1fVDjSdSjXjQxgsoraBDx?filename=bear_05_metadata.json",
        "https://gateway.pinata.cloud/ipfs/QmXD7gDbpspVVvjAwWojeFKPFaQVArweiXmWuZ41uMozDE?filename=bear_06_metadata.json"
    ];

    event TokensUpdated(string Trend);

    constructor(uint256 updateInterval, uint64 vrfSubscriptionId, address _priceFeed, address vrfCoordinator) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(vrfCoordinator) {
        // Sets the keeper update interval
        interval = updateInterval;
        lastTimeStamp = block.timestamp;

        // set the price feed address to
        // ETH/USD Price Feed Contract Address on Polygon Mumbai: 0x0715A7794a1dc8e42615F059dD6e406A6594651A
        // https://mumbai.polygonscan.com/address/0x0715A7794a1dc8e42615F059dD6e406A6594651A
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

        // Return price without value decimal part
        return price / 100000000;
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
