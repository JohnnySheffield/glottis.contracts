// src/interfaces/IUniswapV2Factory.sol
pragma solidity ^0.8.4;

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
