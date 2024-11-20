// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { Utils } from "../../libraries/Utils.sol";
import { IBeraChef } from "../interfaces/IBeraChef.sol";
import { IBerachainRewardsVault } from "../interfaces/IBerachainRewardsVault.sol";
import { StakingRewards } from "./StakingRewards.sol";

/// @title Berachain Zeroelend Rewards Vault
/// @author Berachain-Zerolend Team
/// @notice This contract is the vault for the Berachain rewards, it handles the staking and rewards accounting of BGT.
/// @dev This contract is taken from the stable and tested:
/// https://github.com/Synthetixio/synthetix/blob/develop/contracts/StakingRewards.sol
/// We are using this model instead of 4626 because we want to incentivize staying in the vault for x period of time to
/// to be considered a 'miner' and not a 'trader'.
contract BerachainZerolendRewardsVault is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    StakingRewards,
    IBerachainRewardsVault
{
    using Utils for bytes4;
    using SafeTransferLib for address;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Struct to hold delegate stake data.
    /// @param delegateTotalStaked The total amount staked by delegates.
    /// @param stakedByDelegate The mapping of the amount staked by each delegate.
    struct DelegateStake {
        uint256 delegateTotalStaked;
        mapping(address delegate => uint256 amount) stakedByDelegate;
    }

    /// @notice Struct to hold an incentive data.
    /// @param minIncentiveRate The minimum amount of the token to incentivize per BGT emission.
    /// @param incentiveRate The amount of the token to incentivize per BGT emission.
    /// @param amountRemaining The amount of the token remaining to incentivize.
    struct Incentive {
        uint256 minIncentiveRate;
        uint256 incentiveRate;
        uint256 amountRemaining;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice The maximum count of incentive tokens that can be stored.
    uint8 public maxIncentiveTokensCount;

    /// @notice The address of the distributor contract.
    address public distributor;

    /// @notice The Berachef contract.
    IBeraChef public beraChef;

    mapping(address account => DelegateStake) internal _delegateStake;

    /// @notice The mapping of accounts to their operators.
    mapping(address account => address operator) internal _operators;

    /// @notice the mapping of incentive token to its incentive data.
    mapping(address token => Incentive incentives) public incentives;

    /// @notice The list of whitelisted tokens.
    address[] public whitelistedTokens;

    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IBerachainRewardsVault
    function initialize(
        address _bgt,
        address _distributor,
        address _berachef,
        address _governance,
        address _stakingToken
    )
        external
        initializer
    {
        __Ownable_init(_governance);
        __StakingRewards_init(_stakingToken, _bgt, 7 days);
        maxIncentiveTokensCount = 3;
        // slither-disable-next-line missing-zero-check
        distributor = _distributor;
        beraChef = IBeraChef(_berachef);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyDistributor() {
        if (msg.sender != distributor) NotDistributor.selector.revertWith();
        _;
    }

    modifier onlyOperatorOrUser(address account) {
        if (msg.sender != account) {
            if (msg.sender != _operators[account]) NotOperator.selector.revertWith();
        }
        _;
    }

    modifier checkSelfStakedBalance(address account, uint256 amount) {
        _checkSelfStakedBalance(account, amount);
        _;
    }

    modifier onlyWhitelistedToken(address token) {
        if (incentives[token].minIncentiveRate == 0) TokenNotWhitelisted.selector.revertWith();
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVault
    function setDistributor(address _rewardDistribution) external onlyOwner {
        if (_rewardDistribution == address(0)) ZeroAddress.selector.revertWith();
        distributor = _rewardDistribution;
        emit DistributorSet(_rewardDistribution);
    }

    /// @inheritdoc IBerachainRewardsVault
    function notifyRewardAmount(address coinbase, uint256 reward) external onlyDistributor {
        _notifyRewardAmount(reward);
        _processIncentives(coinbase, reward);
    }

    /// @inheritdoc IBerachainRewardsVault
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        if (tokenAddress == address(STAKE_TOKEN)) CannotRecoverStakingToken.selector.revertWith();
        tokenAddress.safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /// @inheritdoc IBerachainRewardsVault
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        _setRewardsDuration(_rewardsDuration);
    }

    /// @inheritdoc IBerachainRewardsVault
    function whitelistIncentiveToken(address token, uint256 minIncentiveRate) external onlyOwner {
        Incentive storage incentive = incentives[token];
        if (whitelistedTokens.length == maxIncentiveTokensCount || incentive.minIncentiveRate != 0) {
            TokenAlreadyWhitelistedOrLimitReached.selector.revertWith();
        }
        whitelistedTokens.push(token);
        //set the incentive rate to the minIncentiveRate.
        incentive.incentiveRate = minIncentiveRate;
        incentive.minIncentiveRate = minIncentiveRate;
        emit IncentiveTokenWhitelisted(token, minIncentiveRate);
    }

    /// @inheritdoc IBerachainRewardsVault
    function removeIncentiveToken(address token) external onlyOwner onlyWhitelistedToken(token) {
        delete incentives[token];
        // delete the token from the list.
        _deleteWhitelistedTokenFromList(token);
        emit IncentiveTokenRemoved(token);
    }

    /// @inheritdoc IBerachainRewardsVault
    function setMaxIncentiveTokensCount(uint8 _maxIncentiveTokensCount) external onlyOwner {
        if (_maxIncentiveTokensCount < whitelistedTokens.length) {
            InvalidMaxIncentiveTokensCount.selector.revertWith();
        }
        maxIncentiveTokensCount = _maxIncentiveTokensCount;
        emit MaxIncentiveTokensCountUpdated(_maxIncentiveTokensCount);
    }

    /// @inheritdoc IBerachainRewardsVault
    function pause(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          GETTERS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVault
    function operator(address account) external view returns (address) {
        return _operators[account];
    }

    /// @inheritdoc IBerachainRewardsVault
    function getWhitelistedTokensCount() external view returns (uint256) {
        return whitelistedTokens.length;
    }

    /// @inheritdoc IBerachainRewardsVault
    function getWhitelistedTokens() public view returns (address[] memory) {
        return whitelistedTokens;
    }

    /// @inheritdoc IBerachainRewardsVault
    function getTotalDelegateStaked(address account) external view returns (uint256) {
        return _delegateStake[account].delegateTotalStaked;
    }

    /// @inheritdoc IBerachainRewardsVault
    function getDelegateStake(address account, address delegate) external view returns (uint256) {
        return _delegateStake[account].stakedByDelegate[delegate];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          WRITES                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IBerachainRewardsVault
    function notifyATokenBalances(address account, uint256 amountBefore, uint256 amountAfter) external{
        if (msg.sender != address(STAKE_TOKEN)) NotApprovedSender.selector.revertWith();
        uint256 amount;
        if (amountAfter > amountBefore) {
            amount = amountAfter - amountBefore;
            _stake(account, amount);

            unchecked {
                DelegateStake storage info = _delegateStake[account];
                uint256 delegateStakedBefore = info.delegateTotalStaked;
                uint256 delegateStakedAfter = delegateStakedBefore + amount;
                // `<=` and `<` are equivalent here but the former is cheaper
                if (delegateStakedAfter <= delegateStakedBefore) DelegateStakedOverflow.selector.revertWith();
                info.delegateTotalStaked = delegateStakedAfter;
                // if the total staked by all delegates doesn't overflow, the following won't
                info.stakedByDelegate[msg.sender] += amount;
            }

            emit DelegateStaked(account, msg.sender, amount);

        } else {
            amount = amountBefore - amountAfter;
            unchecked {
                DelegateStake storage info = _delegateStake[account];
                uint256 stakedByDelegate = info.stakedByDelegate[msg.sender];
                if (stakedByDelegate < amount) InsufficientDelegateStake.selector.revertWith();
                info.stakedByDelegate[msg.sender] = stakedByDelegate - amount;
                // underflow not impossible because `info.delegateTotalStaked` >= `stakedByDelegate` >= `amount`
                info.delegateTotalStaked -= amount;
            }

            _withdraw(account, amount);

            emit DelegateWithdrawn(account, msg.sender, amount);
        }
    }

    /// @inheritdoc IBerachainRewardsVault
    /// @dev The operator only handles BGT, not STAKING_TOKEN.
    /// @dev If the operator is the one calling this method, the reward will be credited to their address.
    function getReward(address account) external nonReentrant onlyOperatorOrUser(account) returns (uint256) {
        return _getReward(account, msg.sender);
    }

    /// @inheritdoc IBerachainRewardsVault
    /// @dev Only the account holder can call this function, not the operator.
    function exit() external nonReentrant {
        uint256 amount = _accountInfo[msg.sender].balance;
        _checkSelfStakedBalance(msg.sender, amount);
        _withdraw(msg.sender, amount);
        _getReward(msg.sender, msg.sender);
    }

    /// @inheritdoc IBerachainRewardsVault
    function setOperator(address _operator) external {
        _operators[msg.sender] = _operator;
        emit OperatorSet(msg.sender, _operator);
    }

    /// @inheritdoc IBerachainRewardsVault
    function addIncentive(address token, uint256 amount, uint256 incentiveRate) external onlyWhitelistedToken(token) {
        Incentive storage incentive = incentives[token];
        (uint256 minIncentiveRate, uint256 incentiveRateStored, uint256 amountRemaining) =
            (incentive.minIncentiveRate, incentive.incentiveRate, incentive.amountRemaining);

        // The incentive amount should be equal to or greater than the `minIncentiveRate` to avoid DDOS attacks.
        // If the `minIncentiveRate` is 100 USDC/BGT, the amount should be at least 100 USDC.
        if (amount < minIncentiveRate) AmountLessThanMinIncentiveRate.selector.revertWith();

        token.safeTransferFrom(msg.sender, address(this), amount);
        incentive.amountRemaining = amountRemaining + amount;
        // Allows updating the incentive rate if the remaining incentive is less than the `minIncentiveRate` and
        // the `incentiveRate` is greater than or equal to the `minIncentiveRate`.
        // This will leave some dust but will allow updating the incentive rate without waiting for the
        // `amountRemaining` to become 0.
        if (amountRemaining <= minIncentiveRate && incentiveRate >= minIncentiveRate) {
            incentive.incentiveRate = incentiveRate;
        }
        // Allows increasing the incentive rate, provided the `amount` suffices to incentivize the same amount of BGT.
        // If the current rate is 100 USDC/BGT and the amount remaining is 50 USDC, incentivizing 0.5 BGT,
        // then for a new rate of 150 USDC/BGT, the input amount should be at least 0.5 * (150 - 100) = 25 USDC,
        // ensuring that it will still incentivize 0.5 BGT.
        else if (incentiveRate >= incentiveRateStored) {
            uint256 rateDelta;
            unchecked {
                rateDelta = incentiveRate - incentiveRateStored;
            }
            if (amount >= FixedPointMathLib.mulDiv(amountRemaining, rateDelta, incentiveRateStored)) {
                incentive.incentiveRate = incentiveRate;
            }
        }
        emit IncentiveAdded(token, msg.sender, amount, incentive.incentiveRate);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        INTERNAL FUNCTIONS                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Check if the account has enough self-staked balance.
    /// @param account The account to check the self-staked balance for.
    /// @param amount The amount being withdrawn.
    function _checkSelfStakedBalance(address account, uint256 amount) internal view {
        unchecked {
            uint256 balance = _accountInfo[account].balance;
            uint256 delegateTotalStaked = _delegateStake[account].delegateTotalStaked;
            uint256 selfStaked = balance - delegateTotalStaked;
            if (selfStaked < amount) InsufficientSelfStake.selector.revertWith();
        }
    }

    /// @dev The Distributor grants this contract the allowance to transfer the BGT in its balance.
    function _safeTransferRewardToken(address to, uint256 amount) internal override {
        address(REWARD_TOKEN).safeTransferFrom(distributor, to, amount);
    }

    // Ensure the provided reward amount is not more than the balance in the contract.
    // This keeps the reward rate in the right range, preventing overflows due to
    // very high values of rewardRate in the earned and rewardsPerToken functions;
    // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
    function _checkRewardSolvency() internal view override {
        uint256 allowance = REWARD_TOKEN.allowance(distributor, address(this));
        // TODO: change accounting
        if (undistributedRewards > allowance) InsolventReward.selector.revertWith();
    }

    /// @notice process the incentives for a coinbase.
    /// @param coinbase The coinbase to process the incentives for.
    /// @param bgtEmitted The amount of BGT emitted by the validator.
    function _processIncentives(address coinbase, uint256 bgtEmitted) internal {
        // If the coinbase has set an operator, the operator will receive the incentives.
        // This could be a smart contract or EOA where they can distribute to their delegators or keep if solo.
        // This data is stored in the Berachef contract.
        // If its not set then the coinbase will receive the incentives.
        address _operator = beraChef.getOperator(coinbase);
        if (_operator == address(0)) {
            _operator = coinbase;
        }

        uint256 whitelistedTokensCount = whitelistedTokens.length;
        unchecked {
            for (uint256 i; i < whitelistedTokensCount; ++i) {
                address token = whitelistedTokens[i];
                Incentive storage incentive = incentives[token];
                uint256 amount = FixedPointMathLib.mulDiv(bgtEmitted, incentive.incentiveRate, PRECISION);
                uint256 amountRemaining = incentive.amountRemaining;
                amount = FixedPointMathLib.min(amount, amountRemaining);
                incentive.amountRemaining = amountRemaining - amount;
                // slither-disable-next-line arbitrary-send-erc20
                token.safeTransfer(_operator, amount); // Transfer the incentive to the operator.
                // TODO: avoid emitting events in a loop.
                emit IncentivesProcessed(coinbase, token, bgtEmitted, amount);
            }
        }
    }

    function _deleteWhitelistedTokenFromList(address token) internal {
        uint256 activeTokens = whitelistedTokens.length;
        if (activeTokens == 0) NoWhitelistedTokens.selector.revertWith();
        unchecked {
            for (uint256 i; i < activeTokens; ++i) {
                if (token == whitelistedTokens[i]) {
                    whitelistedTokens[i] = whitelistedTokens[activeTokens - 1];
                    whitelistedTokens.pop();
                    return;
                }
            }
        }
    }
}
