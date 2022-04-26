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
    string public _name;
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

    event UpdatedStrategist(address newStrategist);

    event UpdatedKeeper(address newKeeper);

    event UpdatedRewards(address rewards);

    event UpdatedMinReportDelay(uint256 delay);

    event UpdatedMaxReportDelay(uint256 delay);

    event UpdatedProfitFactor(uint256 profitFactor);

    event UpdatedDebtThreshold(uint256 debtThreshold);

    event EmergencyExitEnabled();

    event UpdatedMetadataURI(string metadataURI);

    event MyLog(string, uint256);

    event Received(address, uint256);

    // The minimum number of seconds between harvest calls. See
    // `setMinReportDelay()` for more details.
    uint256 public minReportDelay;

    // The maximum number of seconds between harvest calls. See
    // `setMaxReportDelay()` for more details.
    uint256 public maxReportDelay;

    // The minimum multiple that `callCost` must be above the credit/profit to
    // be "justifiable". See `setProfitFactor()` for more details.
    uint256 public profitFactor;

    // Use this to adjust the threshold at which running a debt causes a
    // harvest trigger. See `setDebtThreshold()` for more details.
    uint256 public debtThreshold;

    // See note on `setEmergencyExit()`.
    bool public emergencyExit;

    // modifiers
    modifier onlyAuthorized() {
        _onlyAuthorized();
        _;
    }

    // modifier onlyEmergencyAuthorized() {
    //     _onlyEmergencyAuthorized();
    //     _;
    // }

    modifier onlyStrategist() {
        _onlyStrategist();
        _;
    }

    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    modifier onlyRewarder() {
        _onlyRewarder();
        _;
    }

    // modifier onlyKeepers() {
    //     _onlyKeepers();
    //     _;
    // }

    function _onlyAuthorized() internal {
        require(msg.sender == strategist || msg.sender == vault.governance());
    }

    // function _onlyEmergencyAuthorized() internal {
    //     // require(msg.sender == strategist || msg.sender == vault.governance() || msg.sender == vault.guardian() || msg.sender == vault.management());
    // }

    function _onlyStrategist() internal {
        require(msg.sender == strategist);
    }

    function _onlyGovernance() internal {
        require(msg.sender == vault.governance());
    }

    function _onlyRewarder() internal {
        require(msg.sender == vault.governance() || msg.sender == strategist);
    }

    // function _onlyKeepers() internal {
    //     // require(
    //     //     msg.sender == keeper ||
    //     //         msg.sender == strategist ||
    //     //         msg.sender == vault.governance() ||
    //     //         msg.sender == vault.guardian() ||
    //     //         msg.sender == vault.management()
    //     // );
    // }

    constructor(
        address _vault,
        string memory name_,
        address _keeper
    ) {
        _name = name_;
        _initialize(_vault, msg.sender, msg.sender, _keeper);
    }

    function name() public view virtual returns (string memory) {
        return _name;
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

        // initialize variables
        minReportDelay = 0;
        maxReportDelay = 86400;
        profitFactor = 100;
        debtThreshold = 0;

        vault.approve(rewards, type(uint256).max); // Allow rewards to be pulled
    }

    function swapExactInputSingle(uint256 amountIn)
        public
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

    /**
     * @notice
     *  Used to change `strategist`.
     *
     *  This may only be called by governance or the existing strategist.
     * @param _strategist The new address to assign as `strategist`.
     */
    function setStrategist(address _strategist) external onlyAuthorized {
        require(_strategist != address(0));
        strategist = _strategist;
        emit UpdatedStrategist(_strategist);
    }

    /**
     * @notice
     *  Used to change `keeper`.
     *
     *  `keeper` is the only address that may call `tend()` or `harvest()`,
     *  other than `governance()` or `strategist`. However, unlike
     *  `governance()` or `strategist`, `keeper` may *only* call `tend()`
     *  and `harvest()`, and no other authorized functions, following the
     *  principle of least privilege.
     *
     *  This may only be called by governance or the strategist.
     * @param _keeper The new address to assign as `keeper`.
     */
    function setKeeper(address _keeper) external onlyAuthorized {
        require(_keeper != address(0));
        keeper = _keeper;
        emit UpdatedKeeper(_keeper);
    }

    /**
     * @notice
     *  Used to change `rewards`. EOA or smart contract which has the permission
     *  to pull rewards from the vault.
     *
     *  This may only be called by the strategist.
     * @param _rewards The address to use for pulling rewards.
     */
    function setRewards(address _rewards) external onlyRewarder {
        address oldRewards = rewards;
        rewards = _rewards;
        // StrategyLib.internalSetRewards(oldRewards, _rewards, address(vault));
        emit UpdatedRewards(_rewards);
    }

    /**
     * @notice
     *  Used to change `minReportDelay`. `minReportDelay` is the minimum number
     *  of blocks that should pass for `harvest()` to be called.
     *
     *  For external keepers (such as the Keep3r network), this is the minimum
     *  time between jobs to wait. (see `harvestTrigger()`
     *  for more details.)
     *
     *  This may only be called by governance or the strategist.
     * @param _delay The minimum number of seconds to wait between harvests.
     */
    function setMinReportDelay(uint256 _delay) external onlyAuthorized {
        minReportDelay = _delay;
        emit UpdatedMinReportDelay(_delay);
    }

    /**
     * @notice
     *  Used to change `maxReportDelay`. `maxReportDelay` is the maximum number
     *  of blocks that should pass for `harvest()` to be called.
     *
     *  For external keepers (such as the Keep3r network), this is the maximum
     *  time between jobs to wait. (see `harvestTrigger()`
     *  for more details.)
     *
     *  This may only be called by governance or the strategist.
     * @param _delay The maximum number of seconds to wait between harvests.
     */
    function setMaxReportDelay(uint256 _delay) external onlyAuthorized {
        maxReportDelay = _delay;
        emit UpdatedMaxReportDelay(_delay);
    }

    /**
     * @notice
     *  Used to change `profitFactor`. `profitFactor` is used to determine
     *  if it's worthwhile to harvest, given gas costs. (See `harvestTrigger()`
     *  for more details.)
     *
     *  This may only be called by governance or the strategist.
     * @param _profitFactor A ratio to multiply anticipated
     * `harvest()` gas cost against.
     */
    function setProfitFactor(uint256 _profitFactor) external onlyAuthorized {
        profitFactor = _profitFactor;
        emit UpdatedProfitFactor(_profitFactor);
    }

    /**
     * @notice
     *  Sets how far the Strategy can go into loss without a harvest and report
     *  being required.
     *
     *  By default this is 0, meaning any losses would cause a harvest which
     *  will subsequently report the loss to the Vault for tracking. (See
     *  `harvestTrigger()` for more details.)
     *
     *  This may only be called by governance or the strategist.
     * @param _debtThreshold How big of a loss this Strategy may carry without
     * being required to report to the Vault.
     */
    function setDebtThreshold(uint256 _debtThreshold) external onlyAuthorized {
        debtThreshold = _debtThreshold;
        emit UpdatedDebtThreshold(_debtThreshold);
    }

    /**
     * Perform any Strategy unwinding or other calls necessary to capture the
     * "free return" this Strategy has generated since the last time its core
     * position(s) were adjusted. Examples include unwrapping extra rewards.
     * This call is only used during "normal operation" of a Strategy, and
     * should be optimized to minimize losses as much as possible.
     *
     * This method returns any realized profits and/or realized losses
     * incurred, and should return the total amounts of profits/losses/debt
     * payments (in `want` tokens) for the Vault's accounting (e.g.
     * `want.balanceOf(this) >= _debtPayment + _profit`).
     *
     * `_debtOutstanding` will be 0 if the Strategy is not past the configured
     * debt limit, otherwise its value will be how far past the debt limit
     * the Strategy is. The Strategy's debt limit is configured in the Vault.
     *
     * NOTE: `_debtPayment` should be less than or equal to `_debtOutstanding`.
     *       It is okay for it to be less than `_debtOutstanding`, as that
     *       should only used as a guide for how much is left to pay back.
     *       Payments should be made to minimize loss from slippage, debt,
     *       withdrawal fees, etc.
     *
     * See `vault.debtOutstanding()`.
     */
    function prepareReturn()
        public
        virtual
        returns (uint256 _profit, uint256 _loss)
    {
        totalRewards = 0;
        claimComps(address(this));
        uint256 compBalance = balanceOfComp();
        uint256 minCompBalance = 1 * 1e18;
        if (compBalance > minCompBalance) {
            totalRewards = swapExactInputSingle(
                compToken.balanceOf(address(this))
            );
        }

        uint256 totalAssets = cToken.balanceOfUnderlying(address(this));
        uint256 totalDebt = vault.debtOutstanding(address(this));
        console.log("totalAssets", totalAssets, "totalDebt", totalDebt);
        if (totalAssets > totalDebt) {
            _profit = totalAssets - totalDebt + totalRewards;
        } else {
            _loss = totalDebt - totalAssets;
        }
    }

    /**
     * Perform any adjustments to the core position(s) of this Strategy given
     * what change the Vault made in the "investable capital" available to the
     * Strategy. Note that all "free capital" in the Strategy after the report
     * was made is available for reinvestment. Also note that this number
     * could be 0, and you should handle that scenario accordingly.
     *
     * See comments regarding `_debtOutstanding` on `prepareReturn()`.
     */

    /**
     * Liquidate up to `_amountNeeded` of `want` of this strategy's positions,
     * irregardless of slippage. Any excess will be re-invested with `adjustPosition()`.
     * This function should return the amount of `want` tokens made available by the
     * liquidation. If there is a difference between them, `_loss` indicates whether the
     * difference is due to a realized loss, or if there is some other sitution at play
     * (e.g. locked funds) where the amount made available is less than what is needed.
     *
     * NOTE: The invariant `_liquidatedAmount + _loss <= _amountNeeded` should always be maintained
     */

    /**
     * Liquidate everything and returns the amount that got freed.
     * This function is used during emergency exit instead of `prepareReturn()` to
     * liquidate all of the Strategy's positions back to the Vault.
     */

    // function liquidateAllPositions() internal virtual returns (uint256 _amountFreed);

    /**
     * @notice
     *  Provide a signal to the keeper that `tend()` should be called. The
     *  keeper will provide the estimated gas cost that they would pay to call
     *  `tend()`, and this function should use that estimate to make a
     *  determination if calling it is "worth it" for the keeper. This is not
     *  the only consideration into issuing this trigger, for example if the
     *  position would be negatively affected if `tend()` is not called
     *  shortly, then this can return `true` even if the keeper might be
     *  "at a loss" (keepers are always reimbursed by Yearn).
     * @dev
     *  `callCostInWei` must be priced in terms of `wei` (1e-18 ETH).
     *
     *  This call and `harvestTrigger()` should never return `true` at the same
     *  time.
     * @param callCostInWei The keeper's estimated gas cost to call `tend()` (in wei).
     * @return `true` if `tend()` should be called, `false` otherwise.
     */
    // function tendTrigger(uint256 callCostInWei) public view virtual returns (bool) {
    //     // We usually don't need tend, but if there are positions that need
    //     // active maintainence, overriding this function is how you would
    //     // signal for that.
    //     // If your implementation uses the cost of the call in want, you can
    //     // use uint256 callCost = ethToWant(callCostInWei);

    //     return false;
    // }

    /**
     * @notice
     *  Adjust the Strategy's position. The purpose of tending isn't to
     *  realize gains, but to maximize yield by reinvesting any returns.
     *
     *  See comments on `adjustPosition()`.
     *
     *  This may only be called by governance, the strategist, or the keeper.
     */
    // function tend() external onlyKeepers {
    //     // Don't take profits with this call, but adjust for better gains
    //     adjustPosition(vault.debtOutstanding());
    // }

    /**
     * @notice
     *  Provide a signal to the keeper that `harvest()` should be called. The
     *  keeper will provide the estimated gas cost that they would pay to call
     *  `harvest()`, and this function should use that estimate to make a
     *  determination if calling it is "worth it" for the keeper. This is not
     *  the only consideration into issuing this trigger, for example if the
     *  position would be negatively affected if `harvest()` is not called
     *  shortly, then this can return `true` even if the keeper might be "at a
     *  loss" (keepers are always reimbursed by Yearn).
     * @dev
     *  `callCostInWei` must be priced in terms of `wei` (1e-18 ETH).
     *
     *  This call and `tendTrigger` should never return `true` at the
     *  same time.
     *
     *  See `min/maxReportDelay`, `profitFactor`, `debtThreshold` to adjust the
     *  strategist-controlled parameters that will influence whether this call
     *  returns `true` or not. These parameters will be used in conjunction
     *  with the parameters reported to the Vault (see `params`) to determine
     *  if calling `harvest()` is merited.
     *
     *  It is expected that an external system will check `harvestTrigger()`.
     *  This could be a script run off a desktop or cloud bot (e.g.
     *  https://github.com/iearn-finance/yearn-vaults/blob/main/scripts/keep.py),
     *  or via an integration with the Keep3r network (e.g.
     *  https://github.com/Macarse/GenericKeep3rV2/blob/master/contracts/keep3r/GenericKeep3rV2.sol).
     * @param callCostInWei The keeper's estimated gas cost to call `harvest()` (in wei).
     * @return `true` if `harvest()` should be called, `false` otherwise.
     */

    // function harvestTrigger(uint256 callCostInWei) public view virtual returns (bool) {
    //     return
    //         internalHarvestTrigger(
    //             address(vault),
    //             address(this),
    //             ethToWant(callCostInWei),
    //             minReportDelay,
    //             maxReportDelay,
    //             debtThreshold,
    //             profitFactor
    //         );
    // }

    // function internalHarvestTrigger(
    //     address vault,
    //     address strategy,
    //     uint256 callCost,
    //     uint256 minReportDelay,
    //     uint256 maxReportDelay,
    //     uint256 debtThreshold,
    //     uint256 profitFactor
    // ) public view returns (bool) {
    //     StrategyParams memory params = VaultAPI(vault).strategies(strategy);
    //     // Should not trigger if Strategy is not activated
    //     if (params.activation == 0) {
    //         return false;
    //     }

    //     // Should not trigger if we haven't waited long enough since previous harvest
    //     if (block.timestamp.sub(params.lastReport) < minReportDelay) return false;

    //     // Should trigger if hasn't been called in a while
    //     if (block.timestamp.sub(params.lastReport) >= maxReportDelay) return true;

    //     // If some amount is owed, pay it back
    //     // NOTE: Since debt is based on deposits, it makes sense to guard against large
    //     //       changes to the value from triggering a harvest directly through user
    //     //       behavior. This should ensure reasonable resistance to manipulation
    //     //       from user-initiated withdrawals as the outstanding debt fluctuates.
    //     uint256 outstanding = VaultAPI(vault).debtOutstanding();
    //     if (outstanding > debtThreshold) return true;

    //     // Check for profits and losses
    //     uint256 total = StrategyAPI(strategy).estimatedTotalAssets();
    //     // Trigger if we have a loss to report
    //     if (total.add(debtThreshold) < params.totalDebt) return true;

    //     uint256 profit = 0;
    //     if (total > params.totalDebt) profit = total.sub(params.totalDebt); // We've earned a profit!

    //     // Otherwise, only trigger if it "makes sense" economically (gas cost
    //     // is <N% of value moved)
    //     uint256 credit = VaultAPI(vault).creditAvailable();
    //     return (profitFactor.mul(callCost) < credit.add(profit));
    // }

    /**
     * @notice
     *  Harvests the Strategy, recognizing any profits or losses and adjusting
     *  the Strategy's position.
     *
     *  In the rare case the Strategy is in emergency shutdown, this will exit
     *  the Strategy's position.
     *
     *  This may only be called by governance, the strategist, or the keeper.
     * @dev
     *  When `harvest()` is called, the Strategy reports to the Vault (via
     *  `vault.report()`), so in some cases `harvest()` must be called in order
     *  to take in profits, to borrow newly available funds from the Vault, or
     *  otherwise adjust its position. In other cases `harvest()` must be
     *  called to report to the Vault on the Strategy's position, especially if
     *  any losses have occurred.
     */

    function harvest() external returns (uint256) {
        uint256 profit = 0;
        uint256 loss = 0;
        uint256 debtOutstanding = vault.debtOutstanding(address(this));

        // uint256 debtPayment = 0;
        // if (emergencyExit) {
        //     // Free up as much capital as possible
        //     uint256 amountFreed = liquidateAllPositions();
        //     if (amountFreed < debtOutstanding) {
        //         loss = debtOutstanding.sub(amountFreed);
        //     } else if (amountFreed > debtOutstanding) {
        //         profit = amountFreed.sub(debtOutstanding);
        //     }
        //     debtPayment = debtOutstanding.sub(loss);
        // } else {        }
        // Free up returns for Vault to pull
        (profit, loss) = prepareReturn();

        // Allow Vault to take up to the "harvested" balance of this contract,
        // which is the amount it has earned since the last time it reported to
        // the Vault.
        console.log("profit", profit, "loss", loss);
        debtOutstanding = vault.report(profit, loss);
        console.log("debtOutstanding", debtOutstanding);
        uint256 freeAssets = want.balanceOf(address(this));
        console.log("freeAssets", freeAssets);
        adjustPosition(freeAssets);

        // emit Harvested(profit, loss, debtOutstanding);
        lastExecuted = block.timestamp;
        return debtOutstanding;

    }

    function balanceOfComp() public view returns (uint256) {
        return compToken.balanceOf(address(this));
    }

    function adjustPosition(uint256 _debtOutstanding) internal {
        supplyErc20ToCompound(address(want), address(cToken), _debtOutstanding);
    }

    function claimComps(address holder) public {
        IComptroller(compTroller).claimComp(holder);
    }

    function withdraw(uint256 _amountNeeded, bool typeOfRedeem)
        external
        returns (uint256 lossForUser, uint256 amountFreed)
    {

        require(msg.sender == address(vault), "!vault");

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
        console.log('profit',_profit, _loss);
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
        console.log('amountToFreed', amountToFreed, _amountNeeded, profitForUser);
        amountFreed = liquidatePosition(amountToFreed, typeOfRedeem);
        console.log(amountFreed, profitForUser, lossForUser);
        want.safeTransfer(msg.sender, amountFreed);
        vault.reportWithdraw(address(this), amountFreed, profitForUser);
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

    function supplyErc20ToCompound(
        address _erc20Contract,
        address _cErc20Contract,
        uint256 _numTokensToSupply
    ) public returns (uint256) {
        // Create a reference to the underlying asset contract, like DAI.
        ERC20 underlying = ERC20(_erc20Contract);

        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 ceToken = CErc20(_cErc20Contract);

        // Amount of current exchange rate from cToken to underlying
        uint256 exchangeRateMantissa = ceToken.exchangeRateCurrent();
        emit MyLog("Exchange Rate (scaled up): ", exchangeRateMantissa);

        // Amount added to you supply balance this block
        uint256 supplyRateMantissa = ceToken.supplyRatePerBlock();
        emit MyLog("Supply Rate: (scaled up)", supplyRateMantissa);

        // Approve transfer on the ERC20 contract
        underlying.approve(_cErc20Contract, _numTokensToSupply);

        // Mint cTokens
        uint256 mintResult = ceToken.mint(_numTokensToSupply);
        return mintResult;
    }

    function redeemCErc20Tokens(
        uint256 amount,
        bool redeemType,
        address _cErc20Contract
    ) public returns (bool) {
        // Create a reference to the corresponding cToken contract, like cDAI
        CErc20 ceToken = CErc20(_cErc20Contract);

        // `amount` is scaled up, see decimal table here:
        // https://compound.finance/docs#protocol-math

        uint256 redeemResult;

        if (redeemType == true) {
            // Retrieve your asset based on a cToken amount
            redeemResult = ceToken.redeem(amount);
        } else {
            // Retrieve your asset based on an amount of the asset
            redeemResult = ceToken.redeemUnderlying(amount);
        }

        // Error codes are listed here:
        // https://compound.finance/docs/ctokens#error-codes
        emit MyLog("If this is not 0, there was an error", redeemResult);

        return true;
    }
}
