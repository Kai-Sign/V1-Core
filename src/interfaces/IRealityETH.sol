// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title IRealityETH
 * @notice Minimal interface for Reality.eth v3.0 integration
 * @dev See https://reality.eth.limo for full documentation
 *
 * Two versions exist:
 * - RealityETH: Uses native ETH for bonds
 * - RealityETH_ERC20: Uses ERC20 tokens for bonds (e.g., bToken)
 */
interface IRealityETH {
    /**
     * @notice Create a reusable question template
     * @param content JSON template with %s placeholders
     * @return Template ID
     */
    function createTemplate(string memory content) external returns (uint256);

    // ========== ETH VERSION ==========

    /**
     * @notice Ask a question with minimum bond requirement (ETH version)
     * @param template_id Template ID from createTemplate
     * @param question Parameters to fill template placeholders (delimited by ␟)
     * @param arbitrator Address of arbitrator for disputes
     * @param timeout Seconds until answer is final after last activity
     * @param opening_ts When question becomes answerable (0 = immediate)
     * @param nonce Unique value for same question (0 = auto)
     * @param min_bond Minimum bond for first answer
     * @return Question ID
     */
    function askQuestionWithMinBond(
        uint256 template_id,
        string memory question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 min_bond
    ) external payable returns (bytes32);

    // ========== ERC20 VERSION ==========

    /**
     * @notice Ask a question with ERC20 tokens (bToken version)
     * @dev Caller must approve tokens first
     * @param template_id Template ID from createTemplate
     * @param question Parameters to fill template placeholders (delimited by ␟)
     * @param arbitrator Address of arbitrator for disputes
     * @param timeout Seconds until answer is final after last activity
     * @param opening_ts When question becomes answerable (0 = immediate)
     * @param nonce Unique value for same question (0 = auto)
     * @param min_bond Minimum bond for first answer
     * @param tokens Amount of ERC20 tokens to supply as initial bond
     * @return Question ID
     */
    function askQuestionWithMinBondERC20(
        uint256 template_id,
        string memory question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 min_bond,
        uint256 tokens
    ) external returns (bytes32);

    /**
     * @notice Submit an answer with ERC20 tokens
     * @dev Caller must approve tokens first
     * @param question_id The question ID
     * @param answer The answer (bytes32 encoded)
     * @param max_previous Maximum bond of previous answer to replace
     * @param tokens Amount of ERC20 tokens to bond
     */
    function submitAnswerERC20(
        bytes32 question_id,
        bytes32 answer,
        uint256 max_previous,
        uint256 tokens
    ) external;

    /**
     * @notice Submit an answer to a question
     * @param question_id The question ID
     * @param answer The answer (bytes32 encoded)
     * @param max_previous Maximum bond of previous answer to replace
     */
    function submitAnswer(
        bytes32 question_id,
        bytes32 answer,
        uint256 max_previous
    ) external payable;

    /**
     * @notice Check if a question has been finalized
     * @param question_id The question ID
     * @return True if finalized
     */
    function isFinalized(bytes32 question_id) external view returns (bool);

    /**
     * @notice Get the final answer for a finalized question
     * @param question_id The question ID
     * @return The final answer (reverts if not finalized)
     */
    function resultFor(bytes32 question_id) external view returns (bytes32);

    /**
     * @notice Get the best (current) answer for a question
     * @param question_id The question ID
     * @return The current best answer
     */
    function getBestAnswer(bytes32 question_id) external view returns (bytes32);

    /**
     * @notice Get bond for the current best answer
     * @param question_id The question ID
     * @return Bond amount
     */
    function getBond(bytes32 question_id) external view returns (uint256);

    /**
     * @notice Claim winnings from a finalized question
     * @param question_id The question ID
     * @param history_hashes Hashes of answer history
     * @param addrs Addresses who submitted answers
     * @param bonds Bond amounts for each answer
     * @param answers The answers submitted
     */
    function claimWinnings(
        bytes32 question_id,
        bytes32[] memory history_hashes,
        address[] memory addrs,
        uint256[] memory bonds,
        bytes32[] memory answers
    ) external;

    /**
     * @notice Get the finalization timestamp for a question
     * @param question_id The question ID
     * @return Timestamp when question will be finalized (0 if no answer yet)
     */
    function getFinalizeTS(bytes32 question_id) external view returns (uint32);
}
