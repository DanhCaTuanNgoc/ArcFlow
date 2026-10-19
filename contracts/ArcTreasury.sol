// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ArcTreasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAX_BRANCH_ITEMS = 20;

    struct SplitRecipient {
        address addr;
        uint256 bps;
    }

    struct Milestone {
        string description;
        uint256 amount;
        bool released;
    }

    struct StreamBeneficiary {
        address addr;
        uint256 bps;
        uint256 lastClaimTime;
        uint256 claimedAmount;
        uint256 pendingClaim;
        uint256 streamDeposited;
        uint256 cumulativeEntitlementAtConfig;
    }

    struct TreasuryConfig {
        bool configured;
        uint256 splitBps;
        uint256 milestoneBps;
        uint256 streamBps;
        address projectOwner;
        uint256 streamRatePerSecond;
    }

    error NotConfigured();
    error NotProjectOwner();
    error InvalidBps();
    error InvalidStreamRate();
    error ZeroAddress();
    error ZeroAmount();
    error MilestoneAlreadyReleased();
    error MilestoneIndexOutOfBounds();
    error InsufficientMilestoneBalance();
    error NotAStreamBeneficiary();
    error NothingToClaim();
    error NoSplitCredit();
    error TransferFailed();
    error ExistingFundsLocked();
    error DuplicateBeneficiary();
    error DuplicateSplitRecipient();

    event TreasuryConfigured(uint256 splitBps, uint256 milestoneBps, uint256 streamBps, address projectOwner);
    event Deposited(
        address indexed depositor,
        uint256 amount,
        uint256 splitAmount,
        uint256 milestoneAmount,
        uint256 streamAmount
    );
    event MilestoneReleased(uint256 indexed milestoneIndex, address indexed provider, uint256 amount);
    event StreamClaimed(address indexed beneficiary, uint256 amount);
    event SplitClaimed(address indexed recipient, uint256 amount);

    address public immutable usdcToken;
    TreasuryConfig public config;

    SplitRecipient[] public splitRecipients;
    Milestone[] public milestones;
    StreamBeneficiary[] public streamBeneficiaries;

    uint256 public splitBalance;
    uint256 public milestoneBalance;
    uint256 public streamBalance;
    uint256 public totalDeposited;
    uint256 public totalStreamDeposited;

    mapping(address => uint256) public lastClaimedAmount;
    mapping(address => uint256) public splitCredits;

    constructor(address _usdcToken) Ownable(msg.sender) {
        if (_usdcToken == address(0)) revert ZeroAddress();
        usdcToken = _usdcToken;
    }

    function configureTreasury(
        uint256 splitBps,
        uint256 milestoneBps,
        uint256 streamBps,
        address projectOwner,
        uint256 streamRatePerSecond,
        SplitRecipient[] calldata recipients,
        Milestone[] calldata _milestones,
        StreamBeneficiary[] calldata beneficiaries
    ) external onlyOwner {
        if (milestoneBalance > 0 || streamBalance > 0 || splitBalance > 0) revert ExistingFundsLocked();
        if (projectOwner == address(0)) revert ZeroAddress();
        if (splitBps + milestoneBps + streamBps != BPS_DENOMINATOR) revert InvalidBps();
        if (streamBps > 0 && streamRatePerSecond == 0) revert InvalidStreamRate();

        if (recipients.length > MAX_BRANCH_ITEMS || _milestones.length > MAX_BRANCH_ITEMS || beneficiaries.length > MAX_BRANCH_ITEMS)
        {
            revert InvalidBps();
        }

        if (splitBps > 0) {
            if (recipients.length == 0) revert InvalidBps();
            uint256 recipientTotalBps;
            for (uint256 i = 0; i < recipients.length; i++) {
                if (recipients[i].addr == address(0)) revert ZeroAddress();
                recipientTotalBps += recipients[i].bps;
            }
            if (recipientTotalBps != BPS_DENOMINATOR) revert InvalidBps();

            for (uint256 i = 0; i < recipients.length; i++) {
                for (uint256 j = i + 1; j < recipients.length; j++) {
                    if (recipients[i].addr == recipients[j].addr) revert DuplicateSplitRecipient();
                }
            }
        }

        if (milestoneBps > 0 && _milestones.length == 0) revert InvalidBps();

        if (streamBps > 0) {
            if (beneficiaries.length == 0) revert InvalidBps();
            uint256 beneficiaryTotalBps;
            for (uint256 i = 0; i < beneficiaries.length; i++) {
                if (beneficiaries[i].addr == address(0)) revert ZeroAddress();
                beneficiaryTotalBps += beneficiaries[i].bps;
            }
            if (beneficiaryTotalBps != BPS_DENOMINATOR) revert InvalidBps();

            for (uint256 i = 0; i < beneficiaries.length; i++) {
                for (uint256 j = i + 1; j < beneficiaries.length; j++) {
                    if (beneficiaries[i].addr == beneficiaries[j].addr) revert DuplicateBeneficiary();
                }
            }
        }

        uint256 previousBeneficiariesLength = streamBeneficiaries.length;
        for (uint256 i = 0; i < previousBeneficiariesLength; i++) {
            delete lastClaimedAmount[streamBeneficiaries[i].addr];
        }

        delete splitRecipients;
        delete milestones;
        delete streamBeneficiaries;

        splitBalance = 0;
        milestoneBalance = 0;
        streamBalance = 0;
        totalDeposited = 0;

        config = TreasuryConfig({
            configured: true,
            splitBps: splitBps,
            milestoneBps: milestoneBps,
            streamBps: streamBps,
            projectOwner: projectOwner,
            streamRatePerSecond: streamRatePerSecond
        });

        for (uint256 i = 0; i < recipients.length; i++) {
            splitRecipients.push(SplitRecipient({addr: recipients[i].addr, bps: recipients[i].bps}));
        }

        for (uint256 i = 0; i < _milestones.length; i++) {
            if (_milestones[i].amount == 0) revert ZeroAmount();
            milestones.push(Milestone({description: _milestones[i].description, amount: _milestones[i].amount, released: false}));
        }

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            streamBeneficiaries.push(
                StreamBeneficiary({
                    addr: beneficiaries[i].addr,
                    bps: beneficiaries[i].bps,
                    lastClaimTime: block.timestamp,
                    claimedAmount: 0,
                    pendingClaim: 0,
                    streamDeposited: 0,
                    cumulativeEntitlementAtConfig: 0
                })
            );
            lastClaimedAmount[beneficiaries[i].addr] = 0;
        }

        emit TreasuryConfigured(splitBps, milestoneBps, streamBps, projectOwner);
    }

    function depositAndRoute(uint256 amount) external nonReentrant {
        if (!config.configured) revert NotConfigured();
        if (amount == 0) revert ZeroAmount();

        IERC20 token = IERC20(usdcToken);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - balanceBefore;
        if (received == 0) revert ZeroAmount();

        uint256 splitAmount = (received * config.splitBps) / BPS_DENOMINATOR;
        uint256 milestoneAmount = (received * config.milestoneBps) / BPS_DENOMINATOR;
        uint256 streamAmount = received - splitAmount - milestoneAmount;

        splitBalance += splitAmount;
        milestoneBalance += milestoneAmount;
        streamBalance += streamAmount;
        totalDeposited += received;
        totalStreamDeposited += streamAmount;

        if (streamAmount > 0) {
            uint256 beneficiariesLength = streamBeneficiaries.length;
            if (beneficiariesLength > 0) {
                uint256 remainingStreamAmount = streamAmount;
                for (uint256 i = 0; i < beneficiariesLength; i++) {
                    StreamBeneficiary storage beneficiary = streamBeneficiaries[i];
                    uint256 beneficiaryStreamAmount;
                    if (i == beneficiariesLength - 1) {
                        beneficiaryStreamAmount = remainingStreamAmount;
                    } else {
                        beneficiaryStreamAmount = (streamAmount * beneficiary.bps) / BPS_DENOMINATOR;
                        remainingStreamAmount -= beneficiaryStreamAmount;
                    }

                    if (beneficiary.lastClaimTime > 0 && beneficiary.streamDeposited > beneficiary.claimedAmount) {
                        uint256 accrued =
                            ((block.timestamp - beneficiary.lastClaimTime) * config.streamRatePerSecond * beneficiary.bps) /
                            BPS_DENOMINATOR;
                        uint256 depositEntitlement = beneficiary.streamDeposited - beneficiary.claimedAmount;
                        uint256 snapshot = accrued;
                        if (snapshot > depositEntitlement) {
                            snapshot = depositEntitlement;
                        }
                        beneficiary.pendingClaim += snapshot;
                    }

                    beneficiary.lastClaimTime = block.timestamp;
                    beneficiary.streamDeposited += beneficiaryStreamAmount;
                }
            }
        }

        if (splitAmount > 0) {
            uint256 recipientsLength = splitRecipients.length;
            uint256 remainingSplitAmount = splitAmount;

            for (uint256 i = 0; i < recipientsLength; i++) {
                uint256 splitCredit;
                if (i == recipientsLength - 1) {
                    splitCredit = remainingSplitAmount;
                } else {
                    splitCredit = (splitAmount * splitRecipients[i].bps) / BPS_DENOMINATOR;
                    remainingSplitAmount -= splitCredit;
                }

                if (splitCredit > 0) {
                    splitCredits[splitRecipients[i].addr] += splitCredit;
                }
            }
        }

        emit Deposited(msg.sender, received, splitAmount, milestoneAmount, streamAmount);
    }

    function releaseMilestone(uint256 milestoneIndex, address provider) external nonReentrant {
        if (msg.sender != config.projectOwner) revert NotProjectOwner();
        if (provider == address(0)) revert ZeroAddress();
        if (milestoneIndex >= milestones.length) revert MilestoneIndexOutOfBounds();

        Milestone storage milestone = milestones[milestoneIndex];
        if (milestone.released) revert MilestoneAlreadyReleased();
        uint256 milestoneAmount = milestone.amount;
        if (milestoneBalance < milestoneAmount) revert InsufficientMilestoneBalance();

        milestone.released = true;
        milestoneBalance -= milestoneAmount;

        IERC20(usdcToken).safeTransfer(provider, milestoneAmount);

        emit MilestoneReleased(milestoneIndex, provider, milestoneAmount);
    }

    function claimStream() external nonReentrant {
        if (!config.configured) revert NotConfigured();

        (uint256 beneficiaryIndex, bool found) = _findBeneficiary(msg.sender);
        if (!found) revert NotAStreamBeneficiary();

        StreamBeneficiary storage beneficiary = streamBeneficiaries[beneficiaryIndex];

        if (beneficiary.streamDeposited <= beneficiary.claimedAmount) revert NothingToClaim();
        uint256 accrued =
            ((block.timestamp - beneficiary.lastClaimTime) * config.streamRatePerSecond * beneficiary.bps) / BPS_DENOMINATOR;
        uint256 totalClaimable = beneficiary.pendingClaim + accrued;
        uint256 depositEntitlement = beneficiary.streamDeposited - beneficiary.claimedAmount;

        uint256 claimable = totalClaimable;
        if (claimable > depositEntitlement) {
            claimable = depositEntitlement;
        }
        if (claimable > streamBalance) {
            claimable = streamBalance;
        }

        if (claimable == 0) revert NothingToClaim();

        beneficiary.pendingClaim = 0;
        beneficiary.lastClaimTime = block.timestamp;
        beneficiary.claimedAmount += claimable;
        lastClaimedAmount[msg.sender] = claimable;
        streamBalance -= claimable;

        IERC20(usdcToken).safeTransfer(msg.sender, claimable);

        emit StreamClaimed(msg.sender, claimable);
    }

    function claimSplit() external nonReentrant {
        uint256 credit = splitCredits[msg.sender];
        if (credit == 0) revert NoSplitCredit();

        splitCredits[msg.sender] = 0;
        splitBalance -= credit;

        IERC20(usdcToken).safeTransfer(msg.sender, credit);

        emit SplitClaimed(msg.sender, credit);
    }

    function getTreasurySummary()
        external
        view
        returns (
            uint256 _totalDeposited,
            uint256 _splitBalance,
            uint256 _milestoneBalance,
            uint256 _streamBalance,
            uint256 _splitBps,
            uint256 _milestoneBps,
            uint256 _streamBps,
            bool _configured
        )
    {
        _totalDeposited = totalDeposited;
        _splitBalance = splitBalance;
        _milestoneBalance = milestoneBalance;
        _streamBalance = streamBalance;
        _splitBps = config.splitBps;
        _milestoneBps = config.milestoneBps;
        _streamBps = config.streamBps;
        _configured = config.configured;
    }

    function getMilestones() external view returns (Milestone[] memory) {
        return milestones;
    }

    function getSplitRecipients() external view returns (SplitRecipient[] memory) {
        return splitRecipients;
    }

    function getStreamBeneficiaries() external view returns (StreamBeneficiary[] memory) {
        return streamBeneficiaries;
    }

    function getClaimableStream(address beneficiaryAddr) external view returns (uint256) {
        (uint256 beneficiaryIndex, bool found) = _findBeneficiary(beneficiaryAddr);
        if (!found) {
            return 0;
        }

        StreamBeneficiary storage beneficiary = streamBeneficiaries[beneficiaryIndex];
        if (beneficiary.streamDeposited <= beneficiary.claimedAmount) {
            return 0;
        }

        uint256 accrued =
            ((block.timestamp - beneficiary.lastClaimTime) * config.streamRatePerSecond * beneficiary.bps) / BPS_DENOMINATOR;
        uint256 totalClaimable = beneficiary.pendingClaim + accrued;
        uint256 depositEntitlement = beneficiary.streamDeposited - beneficiary.claimedAmount;

        uint256 claimable = totalClaimable;
        if (claimable > depositEntitlement) {
            claimable = depositEntitlement;
        }
        if (claimable > streamBalance) {
            claimable = streamBalance;
        }

        return claimable;
    }

    function _findBeneficiary(address beneficiaryAddr) internal view returns (uint256 index, bool found) {
        uint256 beneficiariesLength = streamBeneficiaries.length;
        for (uint256 i = 0; i < beneficiariesLength; i++) {
            if (streamBeneficiaries[i].addr == beneficiaryAddr) {
                return (i, true);
            }
        }
        return (0, false);
    }
}
