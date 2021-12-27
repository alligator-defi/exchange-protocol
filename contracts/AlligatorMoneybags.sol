// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// The AlligatorMoneybags contract accumulates a portion of Alligator's trading fees and rewards staked GTR holders.
// It handles swapping between GTR and xGTR (Alligator's staking token).
contract AlligatorMoneybags is ERC20("AlligatorMoneybags", "xGTR") {
    using SafeMath for uint256;
    IERC20 public gtr;

    // Define the Alligator token contract.
    constructor(IERC20 _gtr) public {
        gtr = _gtr;
    }

    // Locks GTR and mints xGTR.
    function stake(uint256 _amount) public {
        // Gets the amount of GTRs locked in the contract
        uint256 totalGtr = gtr.balanceOf(address(this));
        // Gets the amount of xGTR in existence
        uint256 totalShares = totalSupply();
        // If no xGTR exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalGtr == 0) {
            _mint(msg.sender, _amount);
        }
        // Calculate and mint the amount of xGTR the GTR is worth. The ratio will change over time, as xGTR is burned/minted and GTR deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount.mul(totalShares).div(totalGtr);
            _mint(msg.sender, what);
        }
        // Lock the GTR in the contract
        gtr.transferFrom(msg.sender, address(this), _amount);
    }

    // Claim back the staked GTRs + gained GTRs.
    function unstake(uint256 _share) public {
        // Gets the amount of xGTR in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of GTR the xGTR is worth
        uint256 what = _share.mul(gtr.balanceOf(address(this))).div(totalShares);
        _burn(msg.sender, _share);
        gtr.transfer(msg.sender, what);
    }
}
