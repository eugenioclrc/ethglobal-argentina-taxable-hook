// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Players is ERC721, Ownable {
    uint256 public playersIdsCounter;
    IERC20 public luc;
    uint256 public constant mintFee = 10e18;
    
    constructor(IERC20 _luc) ERC721('LunaciaPlayers', 'LUNP') Ownable(msg.sender) {
        luc = _luc;
    }

    function mintPlayer() external onlyOwner {
        luc.transferFrom(msg.sender, address(this), mintFee);
        _mint(msg.sender, playersIdsCounter++);
    }
}