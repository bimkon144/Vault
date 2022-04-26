//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


interface IVault is IERC20 {


    function report(
        uint256 _gain,
        uint256 _loss
    ) external returns (uint256);


    function governance() external view returns (address);
    function asset() external view returns (ERC20);
    function creditAvailable() external view returns (uint256);
    function debtOutstanding(address strategy) external view returns (uint256);
    function reportWithdraw(address _strategy, uint256 _assetsAmount, uint256 _profit) external;

}