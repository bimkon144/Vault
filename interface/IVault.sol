//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// EIP-4626: Tokenized Vault Standard - https://eips.ethereum.org/EIPS/eip-4626

interface IVault is IERC20 {


    function report(
        uint256 _gain,
        uint256 _loss
    ) external returns (uint256);


    function governance() external view returns (address);

    function asset() external view returns (ERC20);

    function emergencyShutdown() external view returns (bool);

    function creditAvailable() external view returns (uint256);

    function debtOutstanding(address strategy) external view returns (uint256);

    function syncStrategy(uint256 _gain, uint256 _loss) external;

}