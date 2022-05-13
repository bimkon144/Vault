//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interface/IVault.sol";
import "../interface/IStrategy.sol";
import "hardhat/console.sol";

contract Vault is ERC20, IVault, ReentrancyGuard {
    using SafeERC20 for ERC20;
    ERC20 public immutable asset;
    uint256 public totalDebt;
    uint256 public managementFee;
    address public governance;
    uint256 MAX_BPS;
    uint256 constant SECS_PER_YEAR = 31556952;
    uint256 constant feeDecimals = 4;
    uint256 constant MAXIMUM_STRATEGIES = 20;
    uint256 lastReport;
    bool public emergencyShutdown;
    address[] public withdrawalQueue;

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
        uint256 requestedAssets,
        uint256 shares,
        uint256 receivedAssets
    );

    event StrategyMigrated(
        address oldVersion,
        uint256 gain,
        uint256 loss,
        address newVersion,
        uint256 newTotalDebt
    );

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
        managementFee = 1000; // 1% per year
        MAX_BPS = 10000; // min fee 0,01%
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

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function debtOutstanding(address _strategy) public view returns (uint256) {
        return strategies[_strategy].totalDebt;
    }

    function strategyParams(address _strategy)
        public
        view
        returns (StrategyParams memory)
    {
        return strategies[_strategy];
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this)) + totalDebt;
    }

    function creditAvailable() external view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function syncStrategy(uint256 _gain, uint256 _loss) public nonReentrant {
        require(
            strategies[msg.sender].activation > 0,
            "Only activated strategy"
        );
        if (_gain > 0) {
            strategies[msg.sender].totalGain += _gain;
            totalDebt += _gain;
            _assessFee(msg.sender, _gain);
        }
        if (_loss > 0) {
            strategies[msg.sender].totalLoss += _loss;
            totalDebt -= _loss;
        }
    }

    function migrateStrategy(
        address _oldVersion,
        address _newVersion,
        uint256 _perfomanceFee
    ) external onlyGovernance {
        require(_newVersion != address(0));
        assert(
            strategies[_oldVersion].activation > 0 &&
                strategies[_newVersion].activation == 0
        );
        uint256 profit;
        uint256 loss;
        IStrategy(_oldVersion).toggleStrategyPause();
        (uint256 withdrawedFromOldStrategy, ) = IStrategy(_oldVersion).withdraw(
            asset.balanceOf(_oldVersion),
            true
        );
        asset.safeTransfer(_newVersion, withdrawedFromOldStrategy);

        if (withdrawedFromOldStrategy > strategies[_oldVersion].totalDebt) {
            profit =
                withdrawedFromOldStrategy -
                strategies[_oldVersion].totalDebt;
            strategies[_oldVersion].totalGain += profit;
        } else if (
            strategies[_oldVersion].totalDebt > withdrawedFromOldStrategy
        ) {
            loss =
                strategies[_oldVersion].totalDebt -
                withdrawedFromOldStrategy;
            strategies[_oldVersion].totalLoss += loss;
        }
        strategies[_oldVersion].totalDebt = 0;
        strategies[_oldVersion].activation = 0;

        strategies[_newVersion] = StrategyParams({
            performanceFee: _perfomanceFee,
            activation: block.timestamp,
            lastReport: block.timestamp,
            totalDebt: withdrawedFromOldStrategy,
            totalGain: 0,
            totalLoss: 0
        });

        emit StrategyMigrated(
            _oldVersion,
            profit,
            loss,
            _newVersion,
            withdrawedFromOldStrategy
        );

        for (uint256 i; i < MAXIMUM_STRATEGIES; i++) {
            if (withdrawalQueue[i] == _oldVersion) {
                withdrawalQueue[i] = _newVersion;
                break;
            }
        }
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
        require(
            withdrawalQueue.length < MAXIMUM_STRATEGIES,
            "MAXIMUM_STRATEGIES"
        );
        withdrawalQueue.push(_strategy);
        emit StrategyAdded(_strategy);
    }

    function report(uint256 _gain, uint256 _loss)
        external
        nonReentrant
        returns (uint256)
    {
        require(
            strategies[msg.sender].activation > 0,
            "Only activated strategy"
        );
        uint256 credit = asset.balanceOf(address(this));

        syncStrategy(_gain, _loss);

        if (credit > 0) {
            asset.safeTransfer(msg.sender, credit);
            strategies[msg.sender].totalDebt += credit;
            totalDebt += credit;
        }

        strategies[msg.sender].lastReport = block.timestamp;
        lastReport = block.timestamp;
        emit StrategyReported(msg.sender, _gain, _loss, credit);
        return debtOutstanding(msg.sender);
    }

    function deposit(uint256 assets, address receiver)
        external
        nonReentrant
        returns (uint256 shares)
    {
        assert(!emergencyShutdown);
        require((shares = convertToShares(assets)) != 0, "ZERO_SHARES");
        require(receiver != address(0), "Invalid address");
        asset.safeTransferFrom(msg.sender, address(this), assets);
        shares = convertToShares(assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 _requestedAssets,
        address _receiver,
        address _owner
    ) external nonReentrant returns (uint256 shares) {
        assert(!emergencyShutdown);
        assert(_requestedAssets > 0);
        require(_receiver != address(0), "Invalid address");
        uint256 withdrawingAssets;
        shares = convertToShares(_requestedAssets);
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < _requestedAssets) {
            bool redeemType = false;
            withdrawingAssets = _withdrawFromStrategies(
                _requestedAssets,
                redeemType
            );
        } else {
            withdrawingAssets = _requestedAssets;
        }
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, shares);
        }

        _burn(_owner, shares);

        emit Withdraw(
            msg.sender,
            _receiver,
            _owner,
            _requestedAssets,
            shares,
            withdrawingAssets
        );

        asset.safeTransfer(_receiver, withdrawingAssets);
    }

    function mint(uint256 shares, address receiver)
        external
        nonReentrant
        returns (uint256 assets)
    {
        require((assets = convertToAssets(shares)) != 0, "Vault: ZERO_ASSETS");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function reportWithdraw(
        address _strategy,
        uint256 _amountNeeded,
        uint256 _profit
    ) external {
        require(
            strategies[msg.sender].activation > 0,
            "Only activated strategy"
        );
        if (_profit > 0) {
            _assessFee(_strategy, _profit);
        }
        strategies[_strategy].totalDebt += _amountNeeded;
        totalDebt -= _amountNeeded;
        emit ReportedWithdrawFromStrategy(msg.sender, _amountNeeded, _profit);
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) external nonReentrant returns (uint256 _requestedAssets) {
        require(_receiver != address(0), "Invalid address");
        require(
            (_requestedAssets = convertToAssets(_shares)) != 0,
            "Vault: ZERO_ASSETS"
        );
        uint256 withdrawingAssets;
        if (msg.sender != _owner) {
            _spendAllowance(_owner, msg.sender, _shares);
        }
        assert(_shares > 0);
        _requestedAssets = convertToAssets(_shares);
        uint256 currentBalanceVault = asset.balanceOf(address(this));

        if (currentBalanceVault < _requestedAssets) {
            bool redeemType = true;
            withdrawingAssets = _withdrawFromStrategies(
                _requestedAssets,
                redeemType
            );
        } else {
            withdrawingAssets = _requestedAssets;
        }

        _burn(_owner, _shares);

        emit Withdraw(
            msg.sender,
            _receiver,
            _owner,
            _requestedAssets,
            _shares,
            withdrawingAssets
        );

        asset.safeTransfer(_receiver, withdrawingAssets);
    }

    function _assessFee(address _strategy, uint256 _gain)
        private
        returns (uint256)
    {
        if (
            strategies[_strategy].activation == block.timestamp ||
            _gain == 0 ||
            strategies[_strategy].lastReport == 0
        ) {
            return 0;
        }
        uint256 duration = block.timestamp - strategies[_strategy].lastReport;
        uint256 _managementFee = (strategies[_strategy].totalDebt *
            managementFee *
            duration) / (MAX_BPS * SECS_PER_YEAR);
        uint256 perfomanceFee = (_gain * strategies[_strategy].performanceFee) /
            MAX_BPS;
        uint256 total_fee = perfomanceFee + _managementFee;
        if (total_fee > _gain) {
            total_fee = _gain;
        }
        if (total_fee > _gain) {
            total_fee = _gain;
            uint256 shares = convertToShares(total_fee);
            _mint(governance, shares);
        }
        return total_fee;
    }

    function _withdrawFromStrategies(uint256 _assets, bool _redeemType)
        private
        returns (uint256 summaryAmountToWithdraw)
    {
        address strategy;
        uint256 loss;
        uint256 withdrawedAmount;

        for (uint256 i; i < withdrawalQueue.length; i++) {
            strategy = withdrawalQueue[i];

            uint256 vaultBalance = asset.balanceOf(address(this));

            if (vaultBalance >= _assets) break;

            uint256 amountNeeded = _assets - vaultBalance;

            amountNeeded = Math.min(
                amountNeeded,
                strategies[strategy].totalDebt
            );

            //withdrawingAssets includes personal amount of the tokens depends on loss/profit of the user
            //each strategy make report themselves
            (loss, withdrawedAmount) = IStrategy(strategy).withdraw(
                amountNeeded,
                _redeemType
            );
            summaryAmountToWithdraw += withdrawedAmount;
        }
    }
}
