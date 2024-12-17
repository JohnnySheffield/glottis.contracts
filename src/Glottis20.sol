// SPDX-License-Identifier: BUSL-1.1
// Copyright (C) 2024 Nikola Jokić
pragma solidity ^0.8.4;

import {ERC20} from "lib/solady/src/tokens/ERC20.sol";

contract Glottis20 is ERC20 {
    address public immutable factory;
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    uint256 public immutable maxSupply;
    bool public tradingUnlocked;

    error Unauthorized();
    error TransfersLocked();

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 tokenDecimals,
        uint256 _maxSupply,
        address _factory // Add factory parameter
    ) {
        _name = tokenName;
        _symbol = tokenSymbol;
        _decimals = tokenDecimals;
        maxSupply = _maxSupply;
        factory = _factory; // Set the actual factory address
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != factory) revert Unauthorized();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        if (msg.sender != factory) revert Unauthorized();
        _burn(from, amount);
    }

    function setTradingUnlocked() external {
        if (msg.sender != factory) revert Unauthorized();
        tradingUnlocked = true;
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        if (!tradingUnlocked && from != address(0) && to != address(0) && from != address(this) && to != address(this))
        {
            revert TransfersLocked();
        }
    }
}
