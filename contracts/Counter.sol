// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import "hardhat/console.sol";
import {OpsReady} from "./OpsReady.sol";

interface IOps {
    function createTask(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData
    ) external returns (bytes32 task);
}

contract Counter is OpsReady {
    uint256 public count;
    uint256 public lastExecuted;

    constructor(address payable _ops) OpsReady(_ops) {}
    
    function startTask() external {
        IOps(ops).createTask(
            address(this), 
            this.increaseCount.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
    }
    
    function increaseCount(uint256 amount) external onlyOps {
        require(
            ((block.timestamp - lastExecuted) > 180),
            "Counter: increaseCount: Time not elapsed"
        );

        count += amount;
        lastExecuted = block.timestamp;
    }
    
    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = (block.timestamp - lastExecuted) > 180;

        execPayload = abi.encodeWithSelector(
            this.increaseCount.selector,
            uint256(100)
        );
    }
}