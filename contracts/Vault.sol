//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '../interface/IVault.sol';
import '../interface/IStrategy.sol';
import "hardhat/console.sol";


contract Vault is ERC20, IVault {
    using SafeERC20 for ERC20;
    uint256 public totalDebt;
    uint256 public managementFee;
    uint256 public performanceFee;
    address public governance;
    address public rewards;
    // uint256 public debtRatio;  // Debt ratio for the Vault across all strategies (in BPS, <= 10k)
    ERC20 public immutable asset;
    IStrategy public strategy;
    uint256 constant SECS_PER_YEAR = 31556952;
    uint256 constant feeDecimals = 4;
    uint256 lastReport; 

    struct StrategyParams {
        uint256 performanceFee;
        uint256 activation;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }
    mapping (address => StrategyParams) public strategies; 

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 loss
    );

    constructor(
        string memory _name,
        string memory _symbol,
        address _governance,
        address _rewards,
        ERC20  _asset
    ) ERC20(_name, _symbol) {
        asset = _asset;
        _initialize(_governance, _rewards);
    }

    function _initialize(
        address _governance,
        address _rewards

    ) internal {
        governance = _governance;
        rewards = _rewards;
        managementFee = 1000;
        performanceFee = 200;
    }


    function _assessFee(address _strategy, uint256 gain) internal returns (uint256) {
        if (strategies[_strategy].activation == block.timestamp || gain == 0) {
            return 0;
        }
        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        assert(duration != 0);
        uint256 management_fee = ((strategies[_strategy].totalDebt - ((strategies[_strategy].totalDebt * (10**feeDecimals - managementFee) ) / (10**feeDecimals))) / SECS_PER_YEAR) * duration;

        uint256 performance_fee = gain - ((gain * (10**feeDecimals - performanceFee)) / (10**feeDecimals));
        uint256 total_fee = performance_fee + management_fee;
        if (total_fee > gain) {
            total_fee = gain;
        }
        if (total_fee > 0) {
            uint shares = convertToShares(total_fee);
            _mint(governance, shares);
        }
        return total_fee;
    }

    function addStrategy(
        address _strategy,
        // uint256 _debtRatio,
        // uint256 _minDebtPerHarvest,
        // uint256 _maxDebtPerHarvest,
        uint256 _performanceFee
        // uint256 _profitLimitRatio,
        // uint256 _lossLimitRatio
    ) public {
        strategies[_strategy] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            // debtRatio: _debtRatio,
            // minDebtPerHarvest: _minDebtPerHarvest,
            // maxDebtPerHarvest: _maxDebtPerHarvest,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });
        strategy = IStrategy(_strategy);
    }

    function totalAssets() public view  returns (uint256) {
        return asset.balanceOf(address(this)) + totalDebt;
    }

    function debtOutstanding(address _strategy) public view returns (uint256){
        return strategies[_strategy].totalDebt;
    }

    function creditAvailable() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function reportWithdraw(address _strategy, uint256 _assetsAmount, uint256 _profit) external {
        console.log('lastRp', strategies[msg.sender].lastReport, block.timestamp);
        if (_profit > 0) {
            _assessFee(_strategy, _profit);
        }
        strategies[_strategy].totalDebt += _assetsAmount;
    }

    function report (uint256 gain,  uint256 loss) external returns (uint256){

        uint256 credit = asset.balanceOf(address(this));
        console.log('credit', credit);
        
        if (credit > 0) {
            asset.safeTransfer(msg.sender, credit);
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        }

        if (gain > 0) {
            strategies[msg.sender].totalGain += gain;
            totalDebt += gain;
            _assessFee(msg.sender, gain);
        }

        if (loss > 0) {
            strategies[msg.sender].totalLoss += loss;
            totalDebt -= loss;
        }
        strategies[msg.sender].lastReport = block.timestamp;
        lastReport = block.timestamp;
        return debtOutstanding(msg.sender);

    }

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        require(receiver != address(0), "Invalid address");
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);
        shares = convertToShares(assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        // afterDeposit(assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares, uint256 loss) {
        assert(assets > 0);
        uint256 withdrawingAssets;
        shares = convertToShares(assets); 
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < assets) {

            uint256 amountNeeded = assets - currentBalanceVault;
            bool redeemType = false;
 
            (loss, withdrawingAssets) = IStrategy(strategy).withdraw(amountNeeded, redeemType);  
            console.log(loss,'freed', withdrawingAssets);
        } else {
            withdrawingAssets = assets;
        }
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, withdrawingAssets, shares, loss);

        asset.safeTransfer(receiver, withdrawingAssets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets, uint256 loss) {
        uint256 withdrawingAssets;
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        assert(shares > 0);
        assets = convertToAssets(shares);
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < assets) {
            uint256 amountNeeded = assets - currentBalanceVault;
            bool redeemType = true;
            (loss, withdrawingAssets) = IStrategy(strategy).withdraw(amountNeeded, redeemType);  
        } else {
            withdrawingAssets = assets;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares, loss);

        asset.safeTransfer(receiver, withdrawingAssets);
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : (assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : (shares * totalAssets()) /  supply;
    }

    

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

     function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

}