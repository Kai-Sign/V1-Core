// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {KAIToken} from "./KAIToken.sol";

/**
 * @title KAITokenFactory
 * @notice Factory for deploying KAIToken forks with EIGEN-style intersubjective forking
 * @dev Deploys new KAIToken instances and initializes balances from parent
 */
contract KAITokenFactory {

    // =============================================================================
    //                                  EVENTS
    // =============================================================================
    event ForkCreated(
        address indexed parentToken,
        address indexed newForkToken,
        uint256 parentForkId,
        uint256 newForkId,
        uint256 timestamp,
        uint256 holdersInitialized
    );

    // =============================================================================
    //                              CUSTOM ERRORS
    // =============================================================================
    error Unauthorized();
    error NoHolders();
    error NoAdmins();
    error ZeroAddress();

    /**
     * @notice Create a fork of an existing KAIToken
     * @dev Only callable by admins of the parent token
     * @param parentToken Address of the token to fork
     * @param holders Array of holder addresses to copy balances for
     * @param newAdmins Array of admin addresses for the new fork
     * @return newForkToken Address of the newly deployed fork token
     */
    function createFork(
        address parentToken,
        address[] calldata holders,
        address[] calldata newAdmins
    ) external returns (address newForkToken) {
        if (parentToken == address(0)) revert ZeroAddress();
        if (holders.length == 0) revert NoHolders();
        if (newAdmins.length == 0) revert NoAdmins();

        KAIToken parent = KAIToken(parentToken);

        // Verify caller is admin of parent token
        if (!parent.hasRole(parent.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }

        // Mark parent as forked
        parent.markAsForked();

        uint256 parentForkId = parent.forkId();
        uint256 newForkId = parentForkId + parent.forkCount() + 1;

        // Generate fork name and symbol
        string memory forkName = string(abi.encodePacked(parent.name(), " Fork ", _toString(newForkId)));
        string memory forkSymbol = string(abi.encodePacked(parent.symbol(), "-F", _toString(newForkId)));

        // Deploy new fork token
        KAIToken newToken = new KAIToken(
            forkName,
            forkSymbol,
            newAdmins,
            0, // No initial supply, will initialize from parent balances
            newForkId,
            parentToken
        );

        newForkToken = address(newToken);

        // Register child fork in parent
        parent.registerChildFork(newForkToken);

        // Initialize balances in the new fork
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if (holder == address(0)) continue;

            uint256 balance = parent.balanceOf(holder);
            if (balance > 0) {
                newToken.mint(holder, balance);
            }
        }

        emit ForkCreated(
            parentToken,
            newForkToken,
            parentForkId,
            newForkId,
            block.timestamp,
            holders.length
        );
    }

    /**
     * @dev Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
