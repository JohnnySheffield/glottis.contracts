// script/DeployAndTest.s.sol
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../src/Glottis20Mint.sol";

contract DeployAndTest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy factory
        address uniswapRouterAddress = 0x920b806E40A00E02E7D2b94fFc89860fDaEd3640;
        Glottis20Mint Mint = new Glottis20Mint(uniswapRouterAddress, msg.sender);

        bytes memory metadata = abi.encode(
            "https://example.com/token-logo.png", // Logo URL
            "A smol token with flat price points", // Description
            "https://example.com", // Website
            "https://social2.com/whitepaper.pdf", // Social URL 2
            "https://social3.com/whitepaper.pdf" // Social URL 3
        );

        // Create token
        bytes32 salt = bytes32(uint256(12873));
        uint64[4] memory pricePoints = [uint64(1), uint64(1), uint64(1), uint64(1)];

        Mint.createToken("Small Token", "SMOL", 1e18, pricePoints, salt, metadata);

        vm.stopBroadcast();
    }
}
