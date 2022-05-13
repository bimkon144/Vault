//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "../interface/IVault.sol";

interface IStrategy {
    function strategyName() external view returns (string memory);

    function strategist() external view returns (address);
    
    function keeper() external view returns (address);

    function vault() external view returns (IVault _vault);

    function harvest() external returns (uint);

    function withdraw(uint256 _amountNeeded, bool typeOfRedeem) external returns (uint256 _loss, uint256 amountToTransfer);
    
    function lastExecuted() external view returns (uint256);

    function toggleStrategyPause() external;

    function reportDelay() external view returns (uint256);

    function emergencyExit() external view returns (bool);
    
    function strategyPause() external view returns (bool);

    function migrate(address _newStrategy) external returns (uint256 freedAmount);
}