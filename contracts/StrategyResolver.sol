// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {OpsReady} from "../interface/OpsReady.sol";
import "../interface/IStrategy.sol";
import "../interface/IOps.sol";

import "hardhat/console.sol";

contract StrategyResolver is OpsReady {
    address public strategy;

    constructor(address _strategy, address payable _ops) OpsReady(_ops) {
        strategy = _strategy;
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        uint256 lastExecuted = IStrategy(strategy).lastExecuted();
        uint256 reportDelay = IStrategy(strategy).reportDelay();
        bool emergencyExit = IStrategy(strategy).emergencyExit();
        bool strategyPause = IStrategy(strategy).strategyPause();

        canExec = (block.timestamp - lastExecuted) > reportDelay;
        if (emergencyExit || strategyPause) canExec = false;
        execPayload = abi.encodeWithSelector(IStrategy.harvest.selector);
    }

    function startTask() external {
        IOps(ops).createTask(
            strategy,
            IStrategy.harvest.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
    }
}
