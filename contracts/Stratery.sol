//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IStrategy.sol";
import "../interface/IVault.sol";
import "../interface/CErc20.sol";
import "../interface/IComptroller.sol";
import "../interface/IComp.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "hardhat/console.sol";

contract Stratery is IStrategy {
    using SafeERC20 for IERC20;
    string public strategyName;
    address public strategist;
    address public rewards;
    address public keeper;
    CErc20 public cToken;
    IComp public compToken;
    IERC20 public want;
    IComptroller public compTroller;
    IVault public vault;
    ISwapRouter public swapRouter;
    uint24 public constant poolFee = 3000;
    uint256 public totalRewards = 0;
    uint256 public lastExecuted = 0;
    uint256 public reportDelay = 86400;
    bool public emergencyExit;
    bool public strategyPause;

    event UpdatedStrategist(address newStrategist);

    event UpdatedKeeper(address newKeeper);

    event UpdatedReportDelay(uint256 delay);

    event Harvested(uint256 profit, uint256 loss, uint256 debtOutstanding);

    event EmergencyExitEnabled();

    event strategyPauseEnabled();

    modifier onlyAuthorized() {
        require(msg.sender == strategist || msg.sender == vault.governance());
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == vault.governance());
        _;
    }

    modifier onlyKeepers() {
        require(msg.sender == keeper || msg.sender == strategist);
        _;
    }

    modifier onlyEmergencyAuthorized() {
        require(msg.sender == strategist || msg.sender == vault.governance());
        _;
    }

    constructor(
        address _vault,
        string memory _name,
        address _keeper
    ) {
        strategyName = _name;
        _initialize(_vault, msg.sender, msg.sender, _keeper);
    }

    function _initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) internal {
        require(address(want) == address(0), "Strategy already initialized");
        vault = IVault(_vault);
        want = ERC20(vault.asset());
        SafeERC20.safeApprove(want, _vault, type(uint256).max);
        strategist = _strategist;
        rewards = _rewards;
        keeper = _keeper;
        cToken = CErc20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
        compTroller = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
        compToken = IComp(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    }

    function setReportDelay(uint256 _delay) external onlyAuthorized {
        reportDelay = _delay;
        emit UpdatedReportDelay(_delay);
    }

    function setStrategist(address _strategist) external onlyAuthorized {
        require(_strategist != address(0));
        strategist = _strategist;
        emit UpdatedStrategist(_strategist);
    }

    function setKeeper(address _keeper) external onlyAuthorized {
        require(_keeper != address(0));
        keeper = _keeper;
        emit UpdatedKeeper(_keeper);
    }

    function setEmergencyExit() external onlyEmergencyAuthorized {
        emergencyExit = true;
        liquidateAllPositions();
        emit EmergencyExitEnabled();
    }
    function setStrategyPause() external onlyAuthorized {
        strategyPause = true;
        sendAllAssetsToStrategy();
        emit strategyPauseEnabled();
    }

    function harvest() external returns (uint256) {
        uint256 profit = 0;
        uint256 loss = 0;
        uint256 debtOutstanding = vault.debtOutstanding(address(this));

        (profit, loss) = prepareReturn();

        debtOutstanding = vault.report(profit, loss);

        uint256 freeAssets = want.balanceOf(address(this));

        adjustPosition(freeAssets);

        lastExecuted = block.timestamp;
        emit Harvested(profit, loss, debtOutstanding);
        return debtOutstanding;
    }

    function liquidateAllPositions()
        internal
        onlyAuthorized
        returns (uint256 _amountFreed)
    {
         _amountFreed = sendAllAssetsToStrategy();
        want.safeTransfer(vault.governance(), _amountFreed);
    }

    function sendAllAssetsToStrategy () internal returns (uint256 _amountFreed) {
        cToken.redeem(cToken.balanceOf(address(this)));
        uint256 amountOfCompToken = claimComps(address(this));
        uint256 amountOut = swapExactInputSingle(amountOfCompToken);
        uint256 wantStrategyAmount = want.balanceOf(address(this));
        _amountFreed = wantStrategyAmount + amountOut;
    }

    function prepareReturn() internal returns (uint256 _profit, uint256 _loss) {
        totalRewards = 0;
        uint256 compBalance = claimComps(address(this));
        uint256 minCompBalance = 1 * 1e18;
        if (compBalance > minCompBalance) {
            totalRewards = swapExactInputSingle(
                compToken.balanceOf(address(this))
            );
        }

        uint256 totalAssets = cToken.balanceOfUnderlying(address(this));
        uint256 totalDebt = vault.debtOutstanding(address(this));

        if (totalAssets > totalDebt) {
            _profit = totalAssets - totalDebt + totalRewards;
        } else {
            _loss = totalDebt - totalAssets;
        }
    }

    function claimComps(address holder) internal returns (uint256) {
        IComptroller(compTroller).claimComp(holder);
        return compToken.balanceOf(address(this));
    }

    function swapExactInputSingle(uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        // Approve the router to spend DAI.
        TransferHelper.safeApprove(
            address(compToken),
            address(swapRouter),
            amountIn
        );

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: address(compToken),
                tokenOut: address(want),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    function adjustPosition(uint256 _debtOutstanding) internal {
        supplyErc20ToCompound(address(want), address(cToken), _debtOutstanding);
    }

    function supplyErc20ToCompound(
        address _erc20Contract,
        address _cErc20Contract,
        uint256 _numTokensToSupply
    ) internal returns (uint256) {
        ERC20 underlying = ERC20(_erc20Contract);
        CErc20 ceToken = CErc20(_cErc20Contract);

        // Approve transfer on the ERC20 contract
        underlying.approve(_cErc20Contract, _numTokensToSupply);

        // Mint cTokens
        uint256 mintResult = ceToken.mint(_numTokensToSupply);
        return mintResult;
    }

    function withdraw(uint256 _amountNeeded, bool typeOfRedeem)
        external
        returns (uint256 lossForUser, uint256 amountFreed)
    {
        assert(!emergencyExit);
        require(msg.sender == address(vault), "!vault");
        if (want.balanceOf(address(this)) >= _amountNeeded) {
            want.safeTransfer(msg.sender, _amountNeeded);
        } else {
            assert(!strategyPause);
            uint256 _profit;
            uint256 _loss;
            uint256 profitForUser;
            uint256 totalAssets = cToken.balanceOfUnderlying(address(this));
            uint256 totalDebt = vault.debtOutstanding(address(this));
            if (totalAssets > totalDebt) {
                _profit = totalAssets - totalDebt + totalRewards;
            } else {
                _loss = totalDebt - totalAssets;
            }

            if (_profit > 0) {
                profitForUser = (_amountNeeded * _profit) / totalAssets;
            } else {
                profitForUser = 0;
            }
            if (_loss > 0) {
                lossForUser = (_amountNeeded * _loss) / totalAssets;
            } else {
                lossForUser = 0;
            }

            uint256 amountToFreed = _amountNeeded + profitForUser - lossForUser;

            amountFreed = liquidatePosition(amountToFreed, typeOfRedeem);
            want.safeTransfer(msg.sender, amountFreed);
            vault.reportWithdraw(address(this), amountFreed, profitForUser);
        }
    }

    function liquidatePosition(uint256 _amountNeeded, bool typeOfRedeem)
        internal
        virtual
        returns (uint256 _liquidatedAmount)
    {
        bool liquidatedAmount = redeemCErc20Tokens(
            _amountNeeded,
            typeOfRedeem,
            address(cToken)
        );
        if (liquidatedAmount) {
            _liquidatedAmount = want.balanceOf(address(this));
        }
    }

    function redeemCErc20Tokens(
        uint256 amount,
        bool redeemType,
        address _cErc20Contract
    ) internal returns (bool) {
        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 ceToken = CErc20(_cErc20Contract);

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = ceToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = ceToken.redeemUnderlying(amount);
        }

        return true;
    }
}
