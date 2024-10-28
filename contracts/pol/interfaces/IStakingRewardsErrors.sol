// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @notice Interface of staking rewards errors
interface IStakingRewardsErrors {
    error InsolventReward();
    error InsufficientStake();
    error RewardCycleNotEnded();
    error StakeAmountIsZero();
    error TotalSupplyOverflow();
    error WithdrawAmountIsZero();
    error RewardsDurationIsZero();
}
