// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 Nikola Jokić
pragma solidity ^0.8.4;

import "./Glottis20.sol";

import "lib/solady/src/utils/CREATE3.sol";
import "lib/solady/src/utils/FixedPointMathLib.sol";
import "lib/solady/src/utils/SSTORE2.sol";
import "lib/solady/src/utils/ReentrancyGuard.sol";
import "lib/solady/src/utils/SafeTransferLib.sol";

import "./interfaces/IUniswapV2Router02.sol";

contract Glottis20Mint is ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;

    mapping(address => uint256) public pointsMap;
    mapping(address => uint256) public collectedETH;
    mapping(address => address) public meta;

    struct CreatorInfo {
        address creator;
        bytes metadata;
    }

    address public immutable protocolWallet;

    uint256 private constant GWEI_TO_WEI = 1e9;
    uint256 private constant ONE_FULL = 1e18;
    uint256 private constant HUNDRED = 100;

    //fees when creating a new uniswap pool, in eth.
    uint256 public constant PROTOCOL_FEE = 20e14;
    uint256 public constant CREATOR_FEE = 10e14;
    uint256 public constant CALLER_FEE = 5e14;

    //fee on each burn, in eth.
    uint256 public constant BURN_FEE = 35e14;

    uint256 public constant BASIS_POINTS = 10000;

    IUniswapV2Router02 public immutable uniswapRouter;

    event TokenCreated(
        address indexed tokenAddress, string name, string symbol, uint256 maxSupply, uint64[4] pricePoints
    );

    event TokensPurchased(address indexed token, address indexed Minter, uint256 amount, uint256 ethSpent);
    event TokensSold(address indexed token, address indexed Minter, uint256 amount, uint256 ethSpent);
    event UniswapMarketCreated(address indexed token);

    error MaxSupplyReached();
    error InvalidAmount();
    error ETHTransferFailed();
    error InvalidPricePoints();
    error TokenNotFound();
    error InvalidInput();
    error TokenExists();
    error InsufficientPayment();
    error InsufficientLiquidity();
    error InsufficientBalance();
    error CurveNotCompleted();
    error SlippageExceeded();
    error DeploymentFailed();

    constructor(address _router, address _protocolWallet) {
        if (_router == address(0) || _protocolWallet == address(0)) revert InvalidInput();

        uniswapRouter = IUniswapV2Router02(_router);
        protocolWallet = _protocolWallet;
    }

    function createUniswapMarket(address token) external nonReentrant {
        if (pointsMap[token] == 0) revert TokenNotFound();
        Glottis20 glottis20 = Glottis20(token);

        uint256 saleSupply = glottis20.maxSupply() / 2;
        uint256 currentSupply = glottis20.totalSupply();

        if (saleSupply != currentSupply) revert CurveNotCompleted();

        uint256 ethLiquidity = collectedETH[token];

        delete collectedETH[token];

        if (ethLiquidity == 0) revert InsufficientLiquidity();

        uint256 protocolEthFee = ethLiquidity.mulWad(PROTOCOL_FEE);
        uint256 creatorEthFee = ethLiquidity.mulWad(CREATOR_FEE);
        uint256 callerEthFee = ethLiquidity.mulWad(CALLER_FEE);

        uint256 liquidityEth = ethLiquidity.rawSub(protocolEthFee).rawSub(creatorEthFee).rawSub(callerEthFee);

        // Transfer fees
        protocolWallet.forceSafeTransferETH(protocolEthFee);
        readTokenCreator(token).forceSafeTransferETH(creatorEthFee);
        msg.sender.forceSafeTransferETH(callerEthFee);

        glottis20.mint(address(this), currentSupply);

        bool resApproveZero = glottis20.approve(address(uniswapRouter), 0);

        bool resApproveAmnt = glottis20.approve(address(uniswapRouter), type(uint256).max);

        require(resApproveZero && resApproveAmnt, "external call(s) failed");

        uint256 factoryBalance = glottis20.balanceOf(address(this));

        if (factoryBalance < currentSupply) revert InsufficientBalance();

        glottis20.setTradingUnlocked();

        uniswapRouter.addLiquidityETH{value: liquidityEth}(
            token, currentSupply, currentSupply, liquidityEth, address(this), block.timestamp + 15000
        );

        emit UniswapMarketCreated(token);
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 maxSupply,
        uint64[4] calldata pricePoints,
        bytes32 salt,
        bytes memory metadata
    ) external returns (address) {
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidInput();

        if (maxSupply < ONE_FULL || maxSupply > type(uint128).max || maxSupply % 2 != 0) revert InvalidInput();

        if (
            (pricePoints[0] < 1 && pricePoints[0] == type(uint128).max)
                || (pricePoints[1] < 1 && pricePoints[1] == type(uint128).max)
                || (pricePoints[2] < 1 && pricePoints[2] == type(uint128).max)
                || (pricePoints[3] < 1 && pricePoints[0] == type(uint128).max)
        ) {
            revert InvalidPricePoints();
        }
        if (pricePoints[0] < 1 || pricePoints[1] < 1 || pricePoints[2] < 1 || pricePoints[3] < 1) {
            revert InvalidPricePoints();
        }

        address predictedAddress = CREATE3.predictDeterministicAddress(salt);
        if (predictedAddress.code.length > 0) revert TokenExists();

        address tokenAddress = CREATE3.deployDeterministic(
            abi.encodePacked(type(Glottis20).creationCode, abi.encode(name, symbol, 18, maxSupply, address(this))), salt
        );

        if (tokenAddress.code.length == 0) revert DeploymentFailed();

        uint256 packedPrices = uint256(pricePoints[0]) | (uint256(pricePoints[1]) << 64)
            | (uint256(pricePoints[2]) << 128) | (uint256(pricePoints[3]) << 192);

        pointsMap[tokenAddress] = packedPrices;
        bytes memory packedCreatorInfo = abi.encode(CreatorInfo({creator: msg.sender, metadata: metadata}));

        meta[tokenAddress] = SSTORE2.write(packedCreatorInfo);

        emit TokenCreated(tokenAddress, name, symbol, maxSupply, pricePoints);

        return tokenAddress;
    }

    function readTokenCreator(address token) public view returns (address) {
        bytes memory data = SSTORE2.read(meta[token]);
        CreatorInfo memory info = abi.decode(data, (CreatorInfo));
        return info.creator;
    }

    function readTokenMetadata(address token) public view returns (bytes memory) {
        bytes memory data = SSTORE2.read(meta[token]);
        CreatorInfo memory info = abi.decode(data, (CreatorInfo));
        return info.metadata;
    }

    function _unpackPrices(address token) internal view returns (uint64[4] memory prices) {
        uint256 packed = pointsMap[token];
        prices[0] = uint64(packed);
        prices[1] = uint64(packed >> 64);
        prices[2] = uint64(packed >> 128);
        prices[3] = uint64(packed >> 192);
    }

    function calculatePrice(address token, uint256 t) public view returns (uint256) {
        if (pointsMap[token] == 0) revert TokenNotFound();
        if (t > ONE_FULL) revert InvalidAmount();

        uint64[4] memory prices = _unpackPrices(token);

        // For flat curve (all points equal), return the constant price
        if (prices[0] == prices[1] && prices[1] == prices[2] && prices[2] == prices[3]) {
            return uint256(prices[0]).rawMul(GWEI_TO_WEI);
        }

        uint256 ONEMinusT = ONE_FULL.rawSub(t);

        uint256[4] memory pricesWei = [uint256(0), uint256(0), uint256(0), uint256(0)];

        for (uint256 i = 0; i < 4; i++) {
            pricesWei[i] = uint256(prices[i]).rawMul(GWEI_TO_WEI);
        }

        uint256 result;

        // Term 1: (1-t)³ * P0
        result = ONEMinusT.mulWad(ONEMinusT).mulWad(ONEMinusT).mulWad(pricesWei[0]);

        // Term 2: 3(1-t)²t * P1
        result = result.rawAdd(uint256(3).mulWad(ONEMinusT.mulWad(ONEMinusT).mulWad(t)).mulWad(pricesWei[1]));

        // Term 3: 3(1-t)t² * P2
        result = result.rawAdd(uint256(3).mulWad(ONEMinusT.mulWad(t).mulWad(t)).mulWad(pricesWei[2]));

        // Term 4: t³ * P3
        result = result.rawAdd(t.mulWad(t).mulWad(t).mulWad(pricesWei[3]));

        return result;
    }

    function mint(address token, uint256 minTokensOut) external payable nonReentrant {
        if (pointsMap[token] == 0) revert TokenNotFound();
        if (msg.value == 0) revert InvalidAmount();

        (uint256 tokensToMint, uint256 ethToUse) = _calculateMintAmount(token, msg.value);

        if (tokensToMint == 0) revert InsufficientPayment();
        if (tokensToMint < minTokensOut) revert SlippageExceeded();

        _processMint(token, tokensToMint, ethToUse);
    }

    function _calculateMintAmount(address token, uint256 ethIn)
        internal
        view
        returns (uint256 tokensToMint, uint256 ethToUse)
    {
        Glottis20 glottis20 = Glottis20(token);
        uint256 currentSupply = glottis20.totalSupply();
        uint256 STEP_SIZE = glottis20.maxSupply().rawDiv(2).rawDiv(HUNDRED);
        if (glottis20.maxSupply().rawDiv(2) == glottis20.totalSupply()) revert MaxSupplyReached();

        uint256 stepStartSupply = (currentSupply.rawDiv(STEP_SIZE)).rawMul(STEP_SIZE);
        uint256 pricePerFullToken =
            calculatePrice(token, (stepStartSupply.rawMul(ONE_FULL)).rawDiv(glottis20.maxSupply().rawDiv(2)));

        tokensToMint = ethIn.rawMul(ONE_FULL).rawDiv(pricePerFullToken);
        uint256 maxInStep = (stepStartSupply.rawDiv(STEP_SIZE).rawAdd(1).rawMul(STEP_SIZE)).rawSub(currentSupply);

        if (tokensToMint > maxInStep) {
            tokensToMint = maxInStep;
        }

        ethToUse = pricePerFullToken.mulWad(tokensToMint);
    }

    function _processMint(address token, uint256 tokensToMint, uint256 ethToUse) internal {
        if (msg.value > ethToUse) {
            msg.sender.forceSafeTransferETH(msg.value.rawSub(ethToUse));
        }
        collectedETH[token] = collectedETH[token].rawAdd(ethToUse);
        Glottis20(token).mint(msg.sender, tokensToMint);
        emit TokensPurchased(token, msg.sender, tokensToMint, ethToUse);
    }

    function burn(address token, uint256 tokenAmount, uint256 minEthOut) external nonReentrant {
        if (pointsMap[token] == 0) revert TokenNotFound();
        if (tokenAmount == 0) revert InvalidAmount();

        (uint256 tokensToBurn, uint256 ethToReturn, uint256 finalEthAmount) =
            _calculateBurnAmount(token, tokenAmount, minEthOut);
        _processBurn(token, tokensToBurn, ethToReturn, finalEthAmount);
    }

    function _calculateBurnAmount(address token, uint256 tokenAmount, uint256 minEthOut)
        internal
        view
        returns (uint256 tokensToBurn, uint256 ethToReturn, uint256 finalEthAmount)
    {
        Glottis20 glottis20 = Glottis20(token);
        uint256 STEP_SIZE = glottis20.maxSupply().rawDiv(2).rawDiv(HUNDRED);
        uint256 currentSupply = glottis20.totalSupply();

        if (glottis20.maxSupply().rawDiv(2) == glottis20.totalSupply()) revert MaxSupplyReached();

        uint256 stepStartSupply = ((currentSupply - 1).rawDiv(STEP_SIZE)).rawMul(STEP_SIZE);
        uint256 pricePerFullToken =
            calculatePrice(token, (stepStartSupply.rawMul(ONE_FULL)).rawDiv(glottis20.maxSupply().rawDiv(2)));

        uint256 availableInStep = currentSupply.rawSub(stepStartSupply);
        tokensToBurn = tokenAmount > availableInStep ? availableInStep : tokenAmount;
        ethToReturn = pricePerFullToken.mulWad(tokensToBurn);

        if (ethToReturn > collectedETH[token]) revert InsufficientBalance();

        finalEthAmount = ethToReturn.rawSub(ethToReturn.mulWad(BURN_FEE));
        if (finalEthAmount < minEthOut) revert SlippageExceeded();
    }

    function _processBurn(address token, uint256 tokensToBurn, uint256 ethToReturn, uint256 finalEthAmount) internal {
        uint256 feeAmount = ethToReturn.mulWad(BURN_FEE);

        collectedETH[token] = collectedETH[token].rawSub(ethToReturn);

        protocolWallet.forceSafeTransferETH(feeAmount);
        msg.sender.forceSafeTransferETH(finalEthAmount);

        Glottis20(token).burn(msg.sender, tokensToBurn);

        emit TokensSold(token, msg.sender, tokensToBurn, finalEthAmount);
    }

    function predictTokenAddress(bytes32 salt) external view returns (address predictedAddress, bool isDeployed) {
        predictedAddress = CREATE3.predictDeterministicAddress(salt);
        isDeployed = predictedAddress.code.length > 0;
    }
}
