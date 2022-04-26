// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IComp {

    function balanceOf(address account) external view returns (uint);

    function approve(address spender, uint amount) external view returns (bool);

}