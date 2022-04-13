//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface VaultInterface is IERC20 {

    function report(
        uint256 _gain,
        uint256 _loss
    ) external returns (uint256);


    function governance() external view returns (address);


}