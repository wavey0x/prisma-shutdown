pragma solidity ^0.8.13;

import { IPrismaCore } from "src/interfaces/IPrismaCore.sol";

contract CustomPriceFeed {
    address public immutable PRISMA_CORE;

    constructor(address _core) {
        PRISMA_CORE = _core;
    }

    function fetchPrice(address) external returns (uint256) {
        return type(uint256).max / 100e18;
    }

    function owner() external view returns (address) {
        return IPrismaCore(PRISMA_CORE).owner();
    }
}