// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ITroveManager {
    function interestPayable() external view returns (uint256);
    function collectInterests() external returns (bool);
}

interface IFactory {
    function troveManagers(uint256 index) external view returns (address);
    function troveManagersLength() external view returns (uint256);
}

contract InterestCollector {
    IFactory public factory1;
    IFactory public factory2;

    constructor(address _factory1, address _factory2) {
        factory1 = IFactory(_factory1);
        factory2 = IFactory(_factory2);
    }

    function collectInterests() public returns (bool) {
        // Handle both factories
        IFactory[2] memory factories = [factory1, factory2];
        
        for (uint256 f = 0; f < 2; f++) {
            uint256 length = factories[f].troveManagersLength();
            for (uint i = 0; i < length; i++) {
                address tmAddress = factories[f].troveManagers(i);
                ITroveManager tm = ITroveManager(tmAddress);
                
                // Wrap both calls in try-catch to handle potential reverts
                try tm.interestPayable() returns (uint256 amount) {
                    if (amount > 0) {
                        try tm.collectInterests() returns (bool success) {
                            if (!success) {
                                continue; // Skip if collection returns false
                            }
                        } catch {
                            continue; // Skip if collection reverts
                        }
                    }
                } catch {
                    continue; // Skip if interestPayable() reverts
                }
            }
        }

        return true;
    }
}