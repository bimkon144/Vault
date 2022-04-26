//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

interface IStrategy {
    function name() external view returns (string memory);

    function harvest() external returns (uint);

    function withdraw(uint256 _amountNeeded, bool typeOfRedeem) external returns (uint256 _loss, uint256 amountToTransfer);
    
    function lastExecuted() external view returns (uint256);

    function reportDelay() external view returns (uint256);


}