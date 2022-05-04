//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/IVault.sol";
import "../interface/IStrategy.sol";
import "hardhat/console.sol";

contract Vault is ERC20, IVault {
    using SafeERC20 for ERC20;
    ERC20 public immutable asset;
    IStrategy public strategy;
    uint256 public totalDebt;
    uint256 public managementFee;
    uint256 public performanceFee;
    address public governance;
    uint256 constant SECS_PER_YEAR = 31556952;
    uint256 constant feeDecimals = 4;
    uint256 constant MAXIMUM_STRATEGIES = 20;
    uint256 lastReport;
    bool public emergencyShutdown;
    address[MAXIMUM_STRATEGIES] public withdrawalQueue;

    event emergencyShutdownEnabled(bool isActive);

    struct StrategyParams {
        uint256 performanceFee;
        uint256 activation;
        uint256 lastReport;
        uint256 totalDebt;
        uint256 totalGain;
        uint256 totalLoss;
    }
    mapping(address => StrategyParams) public strategies;

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 loss
    );

    event StrategyMigrated(address oldVersion, address newVersion);

    event StrategyAdded(address strategy);

    event StrategyReported(
        address strategy,
        uint256 gain,
        uint256 loss,
        uint256 credit
    );

    event ReportedWithdrawFromStrategy(
        address strategy,
        uint256 amount,
        uint256 profit
    );

    modifier onlyGovernance() {
        require(msg.sender == governance);
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _governance,
        ERC20 _asset
    ) ERC20(_name, _symbol) {
        asset = _asset;
        _initialize(_governance);
    }

    function _initialize(address _governance) internal {
        require(_governance != address(0), "Invalid address");
        governance = _governance;
        managementFee = 1000;
        performanceFee = 200;
    }

    function setEmergencyShutdown(bool _active) external onlyGovernance {
        emergencyShutdown = _active;
        emit emergencyShutdownEnabled(_active);
    }

    function convertToShares(uint256 _assets) public view returns (uint256) {
        uint256 supply = totalSupply();

        return supply == 0 ? _assets : (_assets * supply) / totalAssets();
    }

    function convertToAssets(uint256 _shares) public view returns (uint256) {
        uint256 supply = totalSupply();

        return supply == 0 ? _shares : (_shares * totalAssets()) / supply;
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 _assets) public view returns (uint256) {
        return convertToShares(_assets);
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function debtOutstanding(address _strategy) public view returns (uint256) {
        return strategies[_strategy].totalDebt;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + totalDebt;
    }

    function creditAvailable() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function migrateStrategy(address oldVersion, address newVersion)
        external
        onlyGovernance
    {
        require(newVersion != address(0));
        assert(
            strategies[oldVersion].activation > 0 &&
                strategies[newVersion].activation == 0
        );
        StrategyParams memory oldStrategy = strategies[oldVersion];

        strategies[newVersion] = StrategyParams({
            performanceFee: oldStrategy.performanceFee,
            activation: block.timestamp,
            lastReport: oldStrategy.lastReport,
            totalDebt: oldStrategy.totalDebt,
            totalGain: 0,
            totalLoss: 0
        });

        strategy = IStrategy(newVersion);
        IStrategy(oldVersion).migrate(newVersion);

        emit StrategyMigrated(oldVersion, newVersion);
    }

    function addStrategy(address _strategy, uint256 _performanceFee)
        external
        onlyGovernance
    {
        assert(!emergencyShutdown);
        require(_strategy != address(0), "Invalid address");
        strategies[_strategy] = StrategyParams({
            performanceFee: _performanceFee,
            activation: block.timestamp,
            lastReport: block.timestamp,
            totalDebt: 0,
            totalGain: 0,
            totalLoss: 0
        });
        strategy = IStrategy(_strategy);
        emit StrategyAdded(_strategy);
    }

    function report(uint256 _gain, uint256 _loss) external returns (uint256) {
        require(
            strategies[msg.sender].activation > 0,
            "Only activated strategy"
        );
        uint256 credit = asset.balanceOf(address(this));

        if (credit > 0) {
            asset.safeTransfer(msg.sender, credit);
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        }

        if (_gain > 0) {
            strategies[msg.sender].totalGain += _gain;
            totalDebt += _gain;
            _assessFee(msg.sender, _gain);
        }

        if (_loss > 0) {
            strategies[msg.sender].totalLoss += _loss;
            totalDebt -= _loss;
        }
        strategies[msg.sender].lastReport = block.timestamp;
        lastReport = block.timestamp;
        emit StrategyReported(msg.sender, _gain, _loss, credit);
        return debtOutstanding(msg.sender);
    }

    function reportWithdraw(
        address _strategy,
        uint256 _assetsAmount,
        uint256 _profit
    ) external {
        require(
            strategies[msg.sender].activation > 0,
            "Only activated strategy"
        );
        if (_profit > 0) {
            _assessFee(_strategy, _profit);
        }
        strategies[_strategy].totalDebt += _assetsAmount;
        emit ReportedWithdrawFromStrategy(msg.sender, _assetsAmount, _profit);
    }

    function deposit(uint256 assets, address receiver)
        external
        returns (uint256 shares)
    {
        assert(!emergencyShutdown);
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        require(receiver != address(0), "Invalid address");
        asset.safeTransferFrom(msg.sender, address(this), assets);
        shares = convertToShares(assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) external returns (uint256 shares, uint256 loss) {
        assert(!emergencyShutdown);
        assert(_assets > 0);
        require(_receiver != address(0), "Invalid address");
        uint256 withdrawingAssets;
        shares = convertToShares(_assets);
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < _assets) {
            uint256 amountNeeded = _assets - currentBalanceVault;
            bool redeemType = false;

            (loss, withdrawingAssets) = IStrategy(strategy).withdraw(
                amountNeeded,
                redeemType
            );
        } else {
            withdrawingAssets = _assets;
        }
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, shares);
        }

        _burn(_owner, shares);

        emit Withdraw(
            msg.sender,
            _receiver,
            _owner,
            withdrawingAssets,
            shares,
            loss
        );

        asset.safeTransfer(_receiver, withdrawingAssets);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) external returns (uint256 assets, uint256 loss) {
        require(_receiver != address(0), "Invalid address");
        uint256 withdrawingAssets;
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }
        assert(_shares > 0);
        assets = convertToAssets(_shares);
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < assets) {
            uint256 amountNeeded = assets - currentBalanceVault;
            bool redeemType = true;
            (loss, withdrawingAssets) = IStrategy(strategy).withdraw(
                amountNeeded,
                redeemType
            );
        } else {
            withdrawingAssets = assets;
        }

        _burn(_owner, _shares);

        emit Withdraw(msg.sender, _receiver, _owner, assets, _shares, loss);

        asset.safeTransfer(_receiver, withdrawingAssets);
    }

    function _assessFee(address _strategy, uint256 _gain)
        private
        returns (uint256)
    {
        if (strategies[_strategy].activation == block.timestamp || _gain == 0) {
            return 0;
        }
        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        assert(duration != 0);
        uint256 management_fee = ((strategies[_strategy].totalDebt -
            ((strategies[_strategy].totalDebt *
                (10**feeDecimals - managementFee)) / (10**feeDecimals))) /
            SECS_PER_YEAR) * duration;

        uint256 performance_fee = _gain -
            ((_gain * (10**feeDecimals - performanceFee)) / (10**feeDecimals));
        uint256 total_fee = performance_fee + management_fee;
        if (total_fee > _gain) {
            total_fee = _gain;
        }
        if (total_fee > 0) {
            uint256 shares = convertToShares(total_fee);
            _mint(governance, shares);
        }
        return total_fee;
    }
}
