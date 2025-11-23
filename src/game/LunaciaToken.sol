// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LunaciaToken is ERC20, Ownable {
    constructor() ERC20('Lunacia', 'LUN') Ownable(msg.sender) {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}