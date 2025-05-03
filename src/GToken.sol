// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract GToken is ERC20 {
    constructor() ERC20("GRIT", "GRIT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
