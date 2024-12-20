pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Glottis20Mint.sol";
import "../src/Glottis20.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "../src/interfaces/IUniswapV2Router01.sol";
import "../src/interfaces/IUniswapV2Pair.sol";
import "../src/interfaces/IUniswapV2Factory.sol";

contract Glottis20MintTest is Test {
    Glottis20Mint public glottisMint;
    address public constant UNISWAP_ROUTER = address(0x920b806E40A00E02E7D2b94fFc89860fDaEd3640);
    address public constant PROTOCOL_WALLET = address(0x1);

    address public token;
    address public user = address(0x2);
    uint256 public constant SALE_SUPPLY = 100e18; // 100 tokens
    uint64[4] public PRICE_POINTS = [1, 2, 3, 4]; // 1-4 Gwei progression

    function setUp() public {
        // fico23:
        // this is better because you dont have to do anvil fork etc
        // just make sure .env file has UNICHAIN_TESTNET_RPC_URL set
        // vm.createSelectFork(vm.envString("UNICHAIN_TESTNET_RPC_URL"));
        glottisMint = new Glottis20Mint(UNISWAP_ROUTER, PROTOCOL_WALLET);

        // Create token
        bytes32 salt = bytes32(uint256(1));
        token = glottisMint.createToken("Test Token", "TEST", SALE_SUPPLY * 2, PRICE_POINTS, salt, "");
    }

    function testFullMintBurnCycle() public {
        vm.startPrank(user);
        vm.deal(user, 1000 ether);

        uint256 stepSize = SALE_SUPPLY / 100; // 1% steps

        // Mint a period
        uint256 currentSupply = Glottis20(token).totalSupply();
        uint256 t = (currentSupply * 1e18) / SALE_SUPPLY;
        uint256 price2 = glottisMint.calculatePrice(token, t);
        uint256 ethRequired2 = (price2 * stepSize) / 1e18;

        glottisMint.mint{value: ethRequired2 * 2}(token, 0); // Extra ETH should be refunded

        // Burn a period
        uint256 currentSupply2 = Glottis20(token).totalSupply();
        uint256 BurnAmount = currentSupply2 - ((currentSupply2 - 1) / stepSize) * stepSize;

        uint256 balanceBefore = user.balance;
        glottisMint.burn(token, BurnAmount, 0);
        uint256 balanceAfter = user.balance;

        // Verify received ETH
        assertTrue(balanceAfter > balanceBefore);

        // Mint all periods
        for (uint256 i = 0; i < 100; i++) {
            uint256 currentSupply3 = Glottis20(token).totalSupply();
            uint256 t3 = (currentSupply3 * 1e18) / SALE_SUPPLY;
            uint256 price = glottisMint.calculatePrice(token, t3);
            uint256 ethRequired = (price * stepSize) / 1e18;

            glottisMint.mint{value: ethRequired * 2}(token, 0); // Extra ETH should be refunded
        }

        // Verify total supply after Minting
        assertEq(Glottis20(token).totalSupply(), SALE_SUPPLY);

        // Verify user received all tokens
        assertEq(Glottis20(token).balanceOf(user), SALE_SUPPLY);

        vm.stopPrank();

        // Create Uniswap market
        glottisMint.createUniswapMarket(token);

        // Verify trading is unlocked
        assertTrue(Glottis20(token).tradingUnlocked());

        // Get Uniswap pair
        address pair = IUniswapV2Factory(IUniswapV2Router02(UNISWAP_ROUTER).factory()).getPair(
            token, IUniswapV2Router02(UNISWAP_ROUTER).WETH()
        );
        assertTrue(pair != address(0));

        // Verify liquidity exists
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        assertGt(reserve0, 0);
        assertGt(reserve1, 0);

        // Attempt a trade
        vm.startPrank(user);

        // Assuming the user has tokens, approve the Uniswap router for token transfer
        Glottis20(token).approve(UNISWAP_ROUTER, SALE_SUPPLY);

        // Swap some tokens for ETH (or WETH), using a small amount of tokens for simplicity
        uint256 amountIn = stepSize;
        uint256 amountOutMin = 0; // Testing purposes, usually you'd want this to be calculated
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = IUniswapV2Router02(UNISWAP_ROUTER).WETH();
        uint256 deadline = block.timestamp + 15 minutes;

        balanceAfter = user.balance;

        IUniswapV2Router02(UNISWAP_ROUTER).swapExactTokensForETH(amountIn, amountOutMin, path, user, deadline);

        vm.stopPrank();

        // Verify the trade; check user's ETH balance increased
        assertGt(user.balance, balanceAfter);
    }

    function testSmolAndMaxy() public {
        bytes32 salt1 = bytes32(uint256(2));
        bytes32 salt2 = bytes32(uint256(3));
        address maxxy = glottisMint.createToken(
            "Maxxy Token",
            "MAXX",
            type(uint128).max - 1,
            [type(uint64).max, type(uint64).max, type(uint64).max, type(uint64).max],
            salt1,
            ""
        );
        address smol =
            glottisMint.createToken("Smol Token", "SMOL", 1e18, [uint64(1), uint64(1), uint64(1), uint64(1)], salt2, "");

        vm.startPrank(user);
        vm.deal(user, type(uint256).max);

        uint256 stepSize = (Glottis20(smol).maxSupply() / 2) / 100; // 1% steps
        uint256 stepSize2 = (Glottis20(maxxy).maxSupply() / 2) / 100; // 1% steps

        // Mint a period
        uint256 currentSupply = Glottis20(smol).totalSupply();
        uint256 t = (currentSupply * 1e18) / (Glottis20(smol).maxSupply() / 2);
        uint256 price3 = glottisMint.calculatePrice(smol, t);
        uint256 ethRequired3 = (price3 * stepSize) / 1e18;

        glottisMint.mint{value: ethRequired3 * 2}(smol, 0); // Extra ETH should be refunded

        // Mint a period
        uint256 currentSupply2 = Glottis20(maxxy).totalSupply();
        uint256 t2 = (currentSupply2 * 1e18) / (Glottis20(maxxy).maxSupply() / 2);
        uint256 price4 = glottisMint.calculatePrice(maxxy, t2);
        uint256 ethRequired4 = (price4 * stepSize2) / 1e18;

        glottisMint.mint{value: ethRequired4}(maxxy, 0); // Extra ETH should be refunded
    }

    function testFuzz_FindMaxSafeValue(uint256 maxSupply, uint64 pricePoint) public {
        vm.assume(maxSupply > 1e18); // Ensure minimum reasonable supply
        vm.assume(pricePoint > 0); // Ensure non-zero price

        vm.assume(maxSupply <= type(uint128).max); // Ensure minimum reasonable supply

        try glottisMint.createToken(
            "Fuzz Token",
            "FUZZ",
            maxSupply,
            [pricePoint, pricePoint, pricePoint, pricePoint],
            bytes32(uint256(block.timestamp)),
            ""
        ) returns (address tokenAddress) {
            // If token creation succeeds, try to Mint tokens
            vm.deal(user, type(uint256).max); // Give user maximum ETH
            vm.startPrank(user);

            uint256 stepSize = (maxSupply / 2) / 100; // 1% steps

            try glottisMint.calculatePrice(tokenAddress, 1e18) returns (uint256 price) {
                uint256 ethRequired = (price * stepSize) / 1e18;

                // Try to perform the Mint
                try glottisMint.mint{value: ethRequired}(tokenAddress, 0) {
                    // Log successful values
                    emit log_named_uint("Successful maxSupply", maxSupply);
                    emit log_named_uint("Successful pricePoint", pricePoint);
                    emit log_named_uint("Required ETH", ethRequired);
                } catch {
                    emit log_string("Mint failed");
                }
            } catch {
                emit log_string("Price calculation failed");
            }

            vm.stopPrank();
        } catch {
            emit log_string("Token creation failed");
        }
    }

    // Additional helper test to try specific boundary values
    function testSpecificBoundary() public {
        uint256 maxSupply = type(uint128).max - 1; // Try half of uint256 max
        uint64 pricePoint = type(uint64).max;

        address token2 = glottisMint.createToken(
            "Boundary Token",
            "BOUND",
            maxSupply,
            [pricePoint, pricePoint, pricePoint, pricePoint],
            bytes32(uint256(block.timestamp)),
            ""
        );

        vm.deal(user, type(uint256).max);
        vm.startPrank(user);

        uint256 stepSize = (maxSupply / 2) / 100;
        uint256 price = glottisMint.calculatePrice(token2, 1e18);
        uint256 ethRequired = (price * stepSize) / 1e18;

        // Log values before attempting Mint
        emit log_named_uint("Max Supply", maxSupply);
        emit log_named_uint("Price Point", pricePoint);
        emit log_named_uint("Step Size", stepSize);
        emit log_named_uint("Price", price);
        emit log_named_uint("Required ETH", ethRequired);

        glottisMint.mint{value: ethRequired}(token, 0);

        vm.stopPrank();
    }

    function testTokenTransferRestrictions() public {
        vm.startPrank(user);
        vm.deal(user, 1000 ether);

        // Mint some tokens first
        uint256 stepSize = SALE_SUPPLY / 100; // 1% steps
        uint256 currentSupply = Glottis20(token).totalSupply();
        uint256 t = (currentSupply * 1e18) / SALE_SUPPLY;
        uint256 price = glottisMint.calculatePrice(token, t);
        uint256 ethRequired = (price * stepSize) / 1e18;

        glottisMint.mint{value: ethRequired}(token, 0);

        // Verify user received tokens
        uint256 userBalance = Glottis20(token).balanceOf(user);
        assertGt(userBalance, 0);

        // Try to transfer tokens to another address
        address recipient = address(0x3);
        uint256 transferAmount = userBalance / 2;

        // Updated to expect the correct custom error
        vm.expectRevert(abi.encodeWithSignature("TransfersLocked()"));
        Glottis20(token).transfer(recipient, transferAmount);

        // Try transferFrom as well
        Glottis20(token).approve(address(0x4), transferAmount);

        vm.stopPrank();

        vm.startPrank(address(0x4));
        vm.expectRevert(abi.encodeWithSignature("TransfersLocked()"));
        Glottis20(token).transferFrom(user, recipient, transferAmount);
        vm.stopPrank();
    }

    function testMicroTransferRestrictions() public {
        vm.startPrank(user);
        vm.deal(user, 1000 ether);

        uint256 stepSize = SALE_SUPPLY / 100;
        uint256 currentSupply = Glottis20(token).totalSupply();
        uint256 t = (currentSupply * 1e18) / SALE_SUPPLY;
        uint256 price = glottisMint.calculatePrice(token, t);
        uint256 ethRequired = (price * stepSize) / 1e18;

        glottisMint.mint{value: ethRequired}(token, 0);

        address recipient = address(0x3);

        vm.expectRevert(abi.encodeWithSignature("TransfersLocked()"));
        Glottis20(token).transfer(recipient, 1);

        vm.stopPrank();
    }

    function testZeroTransferRestrictions() public {
        vm.startPrank(user);
        vm.deal(user, 1000 ether);

        uint256 stepSize = SALE_SUPPLY / 100;
        uint256 currentSupply = Glottis20(token).totalSupply();
        uint256 t = (currentSupply * 1e18) / SALE_SUPPLY;
        uint256 price = glottisMint.calculatePrice(token, t);
        uint256 ethRequired = (price * stepSize) / 1e18;

        glottisMint.mint{value: ethRequired}(token, 0);

        address recipient = address(0x3);

        vm.expectRevert(abi.encodeWithSignature("TransfersLocked()"));
        Glottis20(token).transfer(recipient, 0);

        vm.stopPrank();
    }

    function testUniswapTrade(uint256 amount, string memory tradeName) internal {
        Glottis20(token).approve(UNISWAP_ROUTER, amount);

        uint256 balanceBefore = user.balance;
        uint256 tokenBalanceBefore = Glottis20(token).balanceOf(user);

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = IUniswapV2Router02(UNISWAP_ROUTER).WETH();

        IUniswapV2Router02(UNISWAP_ROUTER).swapExactTokensForETH(
            amount,
            0, // min output for testing
            path,
            user,
            block.timestamp + 15 minutes
        );

        uint256 balanceAfter = user.balance;
        uint256 tokenBalanceAfter = Glottis20(token).balanceOf(user);

        assertGt(balanceAfter, balanceBefore, string.concat(tradeName, ": ETH balance should increase"));
        assertEq(
            tokenBalanceAfter,
            tokenBalanceBefore - amount,
            string.concat(tradeName, ": Token balance should decrease exactly")
        );
    }

    receive() external payable {}
}
