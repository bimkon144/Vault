// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface CErc20 {
    function mint(uint256) external returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function supplyRatePerBlock() external returns (uint256);

    function redeem(uint) external returns (uint);

    function redeemUnderlying(uint) external returns (uint);
    
    function balanceOfUnderlying(address owner) external returns (uint);

    function balanceOf(address account) external view returns (uint);
}