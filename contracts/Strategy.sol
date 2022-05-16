//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/IStrategy.sol";
import "../interface/IVault.sol";
import "../interface/CErc20.sol";
import "../interface/IComptroller.sol";
import "../interface/IComp.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "hardhat/console.sol";

contract Strategy is IStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;
    CErc20 public cToken;
    IComp public compToken;
    IERC20 public want;
    IComptroller public compTroller;
    IVault public vault;
    ISwapRouter public swapRouter;
    string public strategyName;
    address public strategist;
    address public rewards;
    address public keeper;
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

    event LiquidatedAllPositions(uint256 amountFreed);

    event LiquidatedPositionAmount(uint256 amountFreed);

    event EmergencyExitEnabled();

    event StrategyPauseToggled(uint256 freedAmount);

    event ClaimedCompTokensAmount(uint256 claimedCompAmount);

    event SwappedCompToWantAmount(uint256 wantAmountOut);

    event AdjustedPosition(uint256 _amountMinted);

    event WithdrawedFromStrategy(
        address strategyAddress,
        uint256 amountWithdrawed
    );

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
        uint256 totalFreedAssets = liquidateAllPositions();
        uint256 totalDebt = vault.debtOutstanding(address(this));
        (uint256 profit, uint256 loss) = calculateProfitLoss(
            totalFreedAssets,
            totalDebt
        );
        vault.syncStrategy(profit, loss);
        emit EmergencyExitEnabled();
    }

    function toggleStrategyPause() public {
        require(
            msg.sender == address(vault) || msg.sender == vault.governance(),
            "can be called by vault or governance"
        );
        strategyPause = !strategyPause;
        if (strategyPause) {
            uint256 amountFreed = sendAllAssetsToStrategy();
            uint256 totalDebt = vault.debtOutstanding(address(this));
            (uint256 profit, uint256 loss) = calculateProfitLoss(
                amountFreed,
                totalDebt
            );
            vault.syncStrategy(profit, loss);
            emit StrategyPauseToggled(amountFreed);
        } else {
            uint256 mintedCTokensAmount = adjustPosition(
                want.balanceOf(address(this))
            );
            emit StrategyPauseToggled(mintedCTokensAmount);
        }
    }

    function harvest() external nonReentrant returns (uint256) {
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
        emit LiquidatedAllPositions(_amountFreed);
    }

    function sendAllAssetsToStrategy() internal returns (uint256 _amountFreed) {
        uint256 amountOut;
        cToken.redeem(cToken.balanceOf(address(this)));
        uint256 amountOfCompToken = claimComps(address(this));
        if (amountOfCompToken > 0) {
            amountOut = swapExactInputSingle(amountOfCompToken);
        }
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

        uint256 totalAssets = cToken.balanceOfUnderlying(address(this)) +
            totalRewards;
        uint256 totalDebt = vault.debtOutstanding(address(this));
        (_profit, _loss) = calculateProfitLoss(totalAssets, totalDebt);
    }

    function calculateProfitLoss(
        uint256 _currentTotalAssets,
        uint256 _totalDebt
    ) internal pure returns (uint256 profit, uint256 loss) {
        _currentTotalAssets > _totalDebt
            ? profit = _currentTotalAssets - _totalDebt
            : loss = _totalDebt - _currentTotalAssets;
    }

    function claimComps(address holder) internal returns (uint256) {
        IComptroller(compTroller).claimComp(holder);
        emit ClaimedCompTokensAmount(compToken.balanceOf(address(this)));
        return compToken.balanceOf(address(this));
    }

    function swapExactInputSingle(uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        TransferHelper.safeApprove(
            address(compToken),
            address(swapRouter),
            amountIn
        );

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

        amountOut = swapRouter.exactInputSingle(params);
        emit SwappedCompToWantAmount(amountOut);
    }

    function adjustPosition(uint256 _debtOutstanding)
        internal
        returns (uint256 mintedTokens)
    {
        supplyErc20ToCompound(_debtOutstanding);
        mintedTokens = cToken.balanceOf(address(this));
        emit AdjustedPosition(mintedTokens);
    }

    function supplyErc20ToCompound(uint256 _numTokensToSupply)
        internal
        returns (uint256)
    {
        want.approve(address(cToken), _numTokensToSupply);
        uint256 mintResult = cToken.mint(_numTokensToSupply);
        return mintResult;
    }

    function withdraw(uint256 _amountNeeded, bool typeOfRedeem)
        external
        nonReentrant
        returns (uint256 amountFreed, uint256 lossForUser)
    {
        assert(!emergencyExit);
        require(msg.sender == address(vault), "!vault");
        if (want.balanceOf(address(this)) >= _amountNeeded) {
            want.safeTransfer(msg.sender, _amountNeeded);
            amountFreed = _amountNeeded;
        } else {
            uint256 _profit;
            uint256 _loss;
            uint256 profitForUser;
            uint256 totalAssetsOnCompound = cToken.balanceOfUnderlying(
                address(this)
            ) + totalRewards;
            uint256 totalStrategyDebt = vault.debtOutstanding(address(this));
            //calculate total profit loss of the strategy and sync with the vault
            (_profit, _loss) = calculateProfitLoss(
                totalAssetsOnCompound,
                totalStrategyDebt
            );
            vault.syncStrategy(_profit, _loss);
            //calculate profit/loss for user that withdrawing
            if (_profit > 0) {
                profitForUser =
                    (_amountNeeded * _profit) /
                    totalAssetsOnCompound;
            } else {
                profitForUser = 0;
            }
            if (_loss > 0) {
                lossForUser = (_amountNeeded * _loss) / totalAssetsOnCompound;
            } else {
                lossForUser = 0;
            }

            uint256 amountToFreed = _amountNeeded + profitForUser - lossForUser;

            amountFreed = liquidatePosition(amountToFreed, typeOfRedeem);
            want.safeTransfer(msg.sender, amountFreed);
            emit WithdrawedFromStrategy(address(this), amountFreed);
        }
    }

    function liquidatePosition(uint256 _amountNeeded, bool typeOfRedeem)
        internal
        virtual
        returns (uint256 _liquidatedAmount)
    {
        bool liquidatedAmount = redeemCErc20Tokens(_amountNeeded, typeOfRedeem);
        if (liquidatedAmount) {
            _liquidatedAmount = want.balanceOf(address(this));
            emit LiquidatedPositionAmount(_liquidatedAmount);
        }
    }

    function redeemCErc20Tokens(uint256 amount, bool redeemType)
        internal
        returns (bool)
    {
        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = cToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = cToken.redeemUnderlying(amount);
        }

        return true;
    }
}
