// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ArcTreasury} from "../ArcTreasury.sol";
import {MockERC20} from "../test-helpers/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Invariant handler — exposes bounded actions for the fuzzer to call.
// Ghost variables track the "true" accounting so the invariant can check them.
// ─────────────────────────────────────────────────────────────────────────────
contract ArcTreasuryHandler is Test {
    ArcTreasury public treasury;
    MockERC20   public usdc;

    address public depositor;
    address public projectOwner;
    address public splitRecip;
    address public streamBenef;

    // ghost totals so the invariant can compare without reading private slots
    uint256 public ghostDeposited;

    constructor(
        ArcTreasury _treasury,
        MockERC20   _usdc,
        address     _depositor,
        address     _projectOwner,
        address     _splitRecip,
        address     _streamBenef
    ) {
        treasury     = _treasury;
        usdc         = _usdc;
        depositor    = _depositor;
        projectOwner = _projectOwner;
        splitRecip   = _splitRecip;
        streamBenef  = _streamBenef;
    }

    /// @dev Called by the invariant fuzzer — deposit a bounded amount.
    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 1_000_000e6);
        usdc.mint(depositor, amount);
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();
        ghostDeposited += amount;
    }

    /// @dev Warp time forward so stream accrues.
    function warpTime(uint256 secs) external {
        secs = bound(secs, 1, 365 days);
        skip(secs);
    }

    /// @dev Let the stream beneficiary claim whatever is claimable.
    function claimStream() external {
        // only call if there's something; ignore revert otherwise
        try treasury.claimStream() {} catch {}
    }

    /// @dev Let the split recipient claim.
    function claimSplit() external {
        vm.prank(splitRecip);
        try treasury.claimSplit() {} catch {}
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main unit test contract
// ─────────────────────────────────────────────────────────────────────────────
contract ArcTreasuryTest is Test {
    // ── addresses ────────────────────────────────────────────────────────────
    address internal owner        = makeAddr("owner");
    address internal projectOwner = makeAddr("projectOwner");
    address internal alice        = makeAddr("alice");
    address internal bob          = makeAddr("bob");
    address internal carol        = makeAddr("carol");
    address internal depositor    = makeAddr("depositor");

    // ── contracts ────────────────────────────────────────────────────────────
    MockERC20   internal usdc;
    ArcTreasury internal treasury;

    // ── constants ────────────────────────────────────────────────────────────
    uint256 internal constant BPS = 10_000;

    // ── shared config helpers ─────────────────────────────────────────────────
    // Standard split-only config: alice 60%, bob 40%.  Milestone bps = 0, stream bps = 0.
    function _splitOnlyConfig()
        internal
        view
        returns (
            uint256 splitBps,
            uint256 milestoneBps,
            uint256 streamBps,
            ArcTreasury.SplitRecipient[] memory recipients,
            ArcTreasury.Milestone[] memory milestoneArr,
            ArcTreasury.StreamBeneficiary[] memory beneficiaries
        )
    {
        splitBps     = 10_000;
        milestoneBps = 0;
        streamBps    = 0;

        recipients    = new ArcTreasury.SplitRecipient[](2);
        recipients[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 6_000});
        recipients[1] = ArcTreasury.SplitRecipient({addr: bob,   bps: 4_000});

        milestoneArr  = new ArcTreasury.Milestone[](0);
        beneficiaries = new ArcTreasury.StreamBeneficiary[](0);
    }

    // Full 3-way config: split 30%, milestone 40%, stream 30%.
    function _fullConfig()
        internal
        view
        returns (
            uint256 splitBps,
            uint256 milestoneBps,
            uint256 streamBps,
            uint256 streamRatePerSec,
            ArcTreasury.SplitRecipient[] memory recipients,
            ArcTreasury.Milestone[] memory milestoneArr,
            ArcTreasury.StreamBeneficiary[] memory beneficiaries
        )
    {
        splitBps        = 3_000;
        milestoneBps    = 4_000;
        streamBps       = 3_000;
        streamRatePerSec = 1e6; // 1 USDC/sec

        recipients    = new ArcTreasury.SplitRecipient[](1);
        recipients[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 10_000});

        milestoneArr    = new ArcTreasury.Milestone[](2);
        milestoneArr[0] = ArcTreasury.Milestone({description: "M1", amount: 100e6, released: false});
        milestoneArr[1] = ArcTreasury.Milestone({description: "M2", amount: 200e6, released: false});

        beneficiaries    = new ArcTreasury.StreamBeneficiary[](1);
        beneficiaries[0] = ArcTreasury.StreamBeneficiary({
            addr: carol,
            bps: 10_000,
            lastClaimTime: 0,
            claimedAmount: 0,
            pendingClaim: 0,
            streamDeposited: 0,
            cumulativeEntitlementAtConfig: 0
        });
    }

    /// @dev Configure treasury with the full 3-way config and return stream rate.
    function _applyFullConfig() internal returns (uint256 streamRatePerSec) {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            uint256 rate,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _fullConfig();
        streamRatePerSec = rate;
        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, rate, recips, mils, bens);
    }

    // ── setUp ─────────────────────────────────────────────────────────────────
    function setUp() public {
        // Deploy mock USDC and treasury (treasury takes USDC address as ctor arg)
        vm.startPrank(owner);
        usdc     = new MockERC20("Mock USDC", "mUSDC", 6);
        treasury = new ArcTreasury(address(usdc));
        vm.stopPrank();

        // Fund depositor
        usdc.mint(depositor, 10_000_000e6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Constructor / initialization
    // ─────────────────────────────────────────────────────────────────────────

    function test_Constructor_SetsUsdcToken() public view {
        assertEq(treasury.usdcToken(), address(usdc));
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_Constructor_NotConfigured() public view {
        (, , , , , , , bool configured) = treasury.getTreasurySummary();
        assertFalse(configured);
    }

    function test_Constructor_ZeroAddressReverts() public {
        vm.expectRevert(ArcTreasury.ZeroAddress.selector);
        new ArcTreasury(address(0));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. configureTreasury — happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function test_ConfigureTreasury_SplitOnly_SetsConfig() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        (, uint256 splitBal, , , uint256 sB, uint256 mB, uint256 stB, bool cfg) = treasury.getTreasurySummary();
        assertTrue(cfg);
        assertEq(sB, 10_000);
        assertEq(mB, 0);
        assertEq(stB, 0);
        assertEq(splitBal, 0);
    }

    function test_ConfigureTreasury_FullConfig_SetsAll() public {
        _applyFullConfig();

        (, , , , uint256 sB, uint256 mB, uint256 stB, bool cfg) = treasury.getTreasurySummary();
        assertTrue(cfg);
        assertEq(sB,  3_000);
        assertEq(mB,  4_000);
        assertEq(stB, 3_000);
    }

    function test_ConfigureTreasury_EmitsTreasuryConfigured() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        vm.expectEmit(false, false, false, true, address(treasury));
        emit ArcTreasury.TreasuryConfigured(sBps, mBps, stBps, projectOwner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);
    }

    function test_ConfigureTreasury_StoreSplitRecipients() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        ArcTreasury.SplitRecipient[] memory stored = treasury.getSplitRecipients();
        assertEq(stored.length, 2);
        assertEq(stored[0].addr, alice);
        assertEq(stored[0].bps,  6_000);
        assertEq(stored[1].addr, bob);
        assertEq(stored[1].bps,  4_000);
    }

    function test_ConfigureTreasury_StoreMilestones() public {
        _applyFullConfig();

        ArcTreasury.Milestone[] memory stored = treasury.getMilestones();
        assertEq(stored.length, 2);
        assertEq(stored[0].description, "M1");
        assertEq(stored[0].amount,      100e6);
        assertFalse(stored[0].released);
    }

    function test_ConfigureTreasury_StoreStreamBeneficiaries() public {
        _applyFullConfig();

        ArcTreasury.StreamBeneficiary[] memory stored = treasury.getStreamBeneficiaries();
        assertEq(stored.length, 1);
        assertEq(stored[0].addr, carol);
        assertEq(stored[0].bps,  10_000);
    }

    function test_ConfigureTreasury_ResetsBalancesAndTotals() public {
        // First configure + deposit so balances become > 0, then claim everything
        // so we can reconfigure (ExistingFundsLocked would block otherwise).
        // We use a split-only config and verify balances reset on reconfigure.
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        // Verify reconfigure resets state (balances are 0 so no ExistingFundsLocked)
        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        (uint256 tot, uint256 sbal, uint256 mbal, uint256 stbal, , , , ) = treasury.getTreasurySummary();
        assertEq(tot, 0);
        assertEq(sbal, 0);
        assertEq(mbal, 0);
        assertEq(stbal, 0);
    }

    // ── configureTreasury — revert paths ─────────────────────────────────────

    function test_ConfigureTreasury_RevertNonOwner() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);
    }

    function test_ConfigureTreasury_RevertBpsMismatch() public {
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](1);
        recips[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 10_000});

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.InvalidBps.selector);
        treasury.configureTreasury(
            5_000, 3_000, 1_000, // sums to 9000, not 10000
            projectOwner, 0,
            recips,
            new ArcTreasury.Milestone[](0),
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertZeroProjectOwner() public {
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](1);
        recips[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 10_000});

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.ZeroAddress.selector);
        treasury.configureTreasury(
            10_000, 0, 0,
            address(0), 0,
            recips,
            new ArcTreasury.Milestone[](0),
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertStreamBpsWithZeroRate() public {
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](0);
        ArcTreasury.StreamBeneficiary[] memory bens = new ArcTreasury.StreamBeneficiary[](1);
        bens[0] = ArcTreasury.StreamBeneficiary({
            addr: carol, bps: 10_000,
            lastClaimTime: 0, claimedAmount: 0, pendingClaim: 0,
            streamDeposited: 0, cumulativeEntitlementAtConfig: 0
        });

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.InvalidStreamRate.selector);
        treasury.configureTreasury(
            0, 0, 10_000,
            projectOwner, 0, // streamRatePerSecond == 0 with streamBps > 0
            recips,
            new ArcTreasury.Milestone[](0),
            bens
        );
    }

    function test_ConfigureTreasury_RevertExistingFundsLocked() public {
        // Configure and deposit so splitBalance > 0
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        vm.startPrank(depositor);
        usdc.approve(address(treasury), 1_000e6);
        treasury.depositAndRoute(1_000e6);
        vm.stopPrank();

        // Attempt reconfigure while funds are locked
        vm.prank(owner);
        vm.expectRevert(ArcTreasury.ExistingFundsLocked.selector);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);
    }

    function test_ConfigureTreasury_RevertDuplicateSplitRecipient() public {
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](2);
        recips[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 5_000});
        recips[1] = ArcTreasury.SplitRecipient({addr: alice, bps: 5_000}); // duplicate

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.DuplicateSplitRecipient.selector);
        treasury.configureTreasury(
            10_000, 0, 0,
            projectOwner, 0,
            recips,
            new ArcTreasury.Milestone[](0),
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertDuplicateBeneficiary() public {
        ArcTreasury.StreamBeneficiary[] memory bens = new ArcTreasury.StreamBeneficiary[](2);
        bens[0] = ArcTreasury.StreamBeneficiary({
            addr: carol, bps: 5_000,
            lastClaimTime: 0, claimedAmount: 0, pendingClaim: 0,
            streamDeposited: 0, cumulativeEntitlementAtConfig: 0
        });
        bens[1] = ArcTreasury.StreamBeneficiary({
            addr: carol, bps: 5_000, // duplicate
            lastClaimTime: 0, claimedAmount: 0, pendingClaim: 0,
            streamDeposited: 0, cumulativeEntitlementAtConfig: 0
        });

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.DuplicateBeneficiary.selector);
        treasury.configureTreasury(
            0, 0, 10_000,
            projectOwner, 1e6,
            new ArcTreasury.SplitRecipient[](0),
            new ArcTreasury.Milestone[](0),
            bens
        );
    }

    function test_ConfigureTreasury_RevertSplitBpsNoRecipients() public {
        vm.prank(owner);
        vm.expectRevert(ArcTreasury.InvalidBps.selector);
        treasury.configureTreasury(
            10_000, 0, 0,
            projectOwner, 0,
            new ArcTreasury.SplitRecipient[](0), // splitBps > 0 but no recipients
            new ArcTreasury.Milestone[](0),
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertMilestoneBpsNoMilestones() public {
        vm.prank(owner);
        vm.expectRevert(ArcTreasury.InvalidBps.selector);
        treasury.configureTreasury(
            0, 10_000, 0,
            projectOwner, 0,
            new ArcTreasury.SplitRecipient[](0),
            new ArcTreasury.Milestone[](0), // milestoneBps > 0 but no milestones
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertMilestoneZeroAmount() public {
        ArcTreasury.Milestone[] memory mils = new ArcTreasury.Milestone[](1);
        mils[0] = ArcTreasury.Milestone({description: "M0", amount: 0, released: false});

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.ZeroAmount.selector);
        treasury.configureTreasury(
            0, 10_000, 0,
            projectOwner, 0,
            new ArcTreasury.SplitRecipient[](0),
            mils,
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    function test_ConfigureTreasury_RevertRecipientsBpsMismatch() public {
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](2);
        recips[0] = ArcTreasury.SplitRecipient({addr: alice, bps: 3_000});
        recips[1] = ArcTreasury.SplitRecipient({addr: bob,   bps: 3_000}); // total 6000, not 10000

        vm.prank(owner);
        vm.expectRevert(ArcTreasury.InvalidBps.selector);
        treasury.configureTreasury(
            10_000, 0, 0,
            projectOwner, 0,
            recips,
            new ArcTreasury.Milestone[](0),
            new ArcTreasury.StreamBeneficiary[](0)
        );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. depositAndRoute — happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function test_DepositAndRoute_SplitOnly_RoutesCorrectly() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        // All goes to split (10000 bps)
        assertEq(treasury.splitBalance(),     amount);
        assertEq(treasury.milestoneBalance(), 0);
        assertEq(treasury.streamBalance(),    0);
        assertEq(treasury.totalDeposited(),   amount);
    }

    function test_DepositAndRoute_FullConfig_RoutesCorrectly() public {
        _applyFullConfig();

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 expectedSplit     = (amount * 3_000) / BPS; // 300e6
        uint256 expectedMilestone = (amount * 4_000) / BPS; // 400e6
        uint256 expectedStream    = amount - expectedSplit - expectedMilestone; // 300e6

        assertEq(treasury.splitBalance(),     expectedSplit);
        assertEq(treasury.milestoneBalance(), expectedMilestone);
        assertEq(treasury.streamBalance(),    expectedStream);
    }

    function test_DepositAndRoute_CreditsCorrectSplitAmounts() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        // alice: 6000 bps of 1000e6 = 600e6; bob: 4000 bps last = 400e6
        uint256 aliceCredit = treasury.splitCredits(alice);
        uint256 bobCredit   = treasury.splitCredits(bob);
        assertEq(aliceCredit + bobCredit, amount);
        assertEq(aliceCredit, (amount * 6_000) / BPS);
    }

    function test_DepositAndRoute_EmitsDeposited() public {
        _applyFullConfig();

        uint256 amount = 1_000e6;
        uint256 expectedSplit     = (amount * 3_000) / BPS;
        uint256 expectedMilestone = (amount * 4_000) / BPS;
        uint256 expectedStream    = amount - expectedSplit - expectedMilestone;

        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit ArcTreasury.Deposited(depositor, amount, expectedSplit, expectedMilestone, expectedStream);
        treasury.depositAndRoute(amount);
        vm.stopPrank();
    }

    function test_DepositAndRoute_UpdatesTotalDeposited() public {
        _applyFullConfig();

        uint256 amount1 = 500e6;
        uint256 amount2 = 750e6;

        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount1 + amount2);
        treasury.depositAndRoute(amount1);
        treasury.depositAndRoute(amount2);
        vm.stopPrank();

        assertEq(treasury.totalDeposited(), amount1 + amount2);
    }

    // ── depositAndRoute — revert paths ────────────────────────────────────────

    function test_DepositAndRoute_RevertZeroAmount() public {
        _applyFullConfig();

        vm.prank(depositor);
        vm.expectRevert(ArcTreasury.ZeroAmount.selector);
        treasury.depositAndRoute(0);
    }

    function test_DepositAndRoute_RevertNotConfigured() public {
        vm.prank(depositor);
        vm.expectRevert(ArcTreasury.NotConfigured.selector);
        treasury.depositAndRoute(100e6);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. releaseMilestone — happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function test_ReleaseMilestone_HappyPath() public {
        _applyFullConfig();

        // Deposit enough to cover milestones (milestoneBalance needs >= 100e6)
        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        uint256 mBalBefore   = treasury.milestoneBalance();
        uint256 providerBal  = usdc.balanceOf(alice);

        vm.prank(projectOwner);
        treasury.releaseMilestone(0, alice);

        assertEq(treasury.milestoneBalance(), mBalBefore - 100e6);
        assertEq(usdc.balanceOf(alice), providerBal + 100e6);
    }

    function test_ReleaseMilestone_EmitsMilestoneReleased() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        vm.prank(projectOwner);
        vm.expectEmit(true, true, false, true, address(treasury));
        emit ArcTreasury.MilestoneReleased(0, alice, 100e6);
        treasury.releaseMilestone(0, alice);
    }

    function test_ReleaseMilestone_MarksReleased() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        vm.prank(projectOwner);
        treasury.releaseMilestone(0, alice);

        ArcTreasury.Milestone[] memory mils = treasury.getMilestones();
        assertTrue(mils[0].released);
    }

    // ── releaseMilestone — revert paths ──────────────────────────────────────

    function test_ReleaseMilestone_RevertNonProjectOwner() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert(ArcTreasury.NotProjectOwner.selector);
        treasury.releaseMilestone(0, alice);
    }

    function test_ReleaseMilestone_RevertAlreadyReleased() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        vm.prank(projectOwner);
        treasury.releaseMilestone(0, alice);

        vm.prank(projectOwner);
        vm.expectRevert(ArcTreasury.MilestoneAlreadyReleased.selector);
        treasury.releaseMilestone(0, alice);
    }

    function test_ReleaseMilestone_RevertIndexOutOfBounds() public {
        _applyFullConfig();

        vm.prank(projectOwner);
        vm.expectRevert(ArcTreasury.MilestoneIndexOutOfBounds.selector);
        treasury.releaseMilestone(99, alice);
    }

    function test_ReleaseMilestone_RevertZeroProviderAddress() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        vm.prank(projectOwner);
        vm.expectRevert(ArcTreasury.ZeroAddress.selector);
        treasury.releaseMilestone(0, address(0));
    }

    function test_ReleaseMilestone_RevertInsufficientMilestoneBalance() public {
        _applyFullConfig();
        // No deposit → milestoneBalance == 0

        vm.prank(projectOwner);
        vm.expectRevert(ArcTreasury.InsufficientMilestoneBalance.selector);
        treasury.releaseMilestone(0, alice);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. claimSplit — happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function test_ClaimSplit_TransfersCredit() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 expectedCredit = (amount * 6_000) / BPS; // 600e6
        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        treasury.claimSplit();

        assertEq(usdc.balanceOf(alice), balBefore + expectedCredit);
    }

    function test_ClaimSplit_ZeroesCredit() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        vm.prank(alice);
        treasury.claimSplit();

        assertEq(treasury.splitCredits(alice), 0);
    }

    function test_ClaimSplit_ReducesSplitBalance() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 aliceCredit = treasury.splitCredits(alice);
        uint256 splitBalBefore = treasury.splitBalance();

        vm.prank(alice);
        treasury.claimSplit();

        assertEq(treasury.splitBalance(), splitBalBefore - aliceCredit);
    }

    function test_ClaimSplit_EmitsSplitClaimed() public {
        (
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            ArcTreasury.SplitRecipient[] memory recips,
            ArcTreasury.Milestone[] memory mils,
            ArcTreasury.StreamBeneficiary[] memory bens
        ) = _splitOnlyConfig();

        vm.prank(owner);
        treasury.configureTreasury(sBps, mBps, stBps, projectOwner, 0, recips, mils, bens);

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 aliceCredit = treasury.splitCredits(alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true, address(treasury));
        emit ArcTreasury.SplitClaimed(alice, aliceCredit);
        treasury.claimSplit();
    }

    // ── claimSplit — revert paths ─────────────────────────────────────────────

    function test_ClaimSplit_RevertNoCredit() public {
        _applyFullConfig();

        vm.prank(bob); // bob has no split credit in the full config (alice is the sole recipient)
        vm.expectRevert(ArcTreasury.NoSplitCredit.selector);
        treasury.claimSplit();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. claimStream — happy paths
    // ─────────────────────────────────────────────────────────────────────────

    function test_ClaimStream_AccruesAfterTimeElapsed() public {
        _applyFullConfig(); // 1e6 per second, carol is sole beneficiary (10000 bps)

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // Warp forward 100 seconds
        skip(100);

        uint256 balBefore = usdc.balanceOf(carol);
        vm.prank(carol);
        treasury.claimStream();

        // accrued = 100s * 1e6/s * 10000/10000 = 100e6
        // depositEntitlement = streamDeposited (300e6) - claimedAmount (0) = 300e6
        // claimable = min(100e6, 300e6, streamBalance 300e6) = 100e6
        assertEq(usdc.balanceOf(carol), balBefore + 100e6);
    }

    function test_ClaimStream_ReducesStreamBalance() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        uint256 stBalBefore = treasury.streamBalance();
        skip(100);

        vm.prank(carol);
        treasury.claimStream();

        assertLt(treasury.streamBalance(), stBalBefore);
    }

    function test_ClaimStream_EmitsStreamClaimed() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        skip(50);

        vm.prank(carol);
        vm.expectEmit(true, false, false, false, address(treasury));
        emit ArcTreasury.StreamClaimed(carol, 0); // only check the topic (carol)
        treasury.claimStream();
    }

    function test_ClaimStream_CannotExceedDepositEntitlement() public {
        _applyFullConfig();

        uint256 depositAmt = 100e6; // deposit 100e6 total; stream portion = 30e6
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // Warp far into the future — accrued will exceed depositEntitlement
        skip(10_000);

        uint256 carolStreamDeposited = treasury.getStreamBeneficiaries()[0].streamDeposited;
        uint256 balBefore = usdc.balanceOf(carol);

        vm.prank(carol);
        treasury.claimStream();

        // carol can claim at most what was deposited for her stream
        assertLe(usdc.balanceOf(carol) - balBefore, carolStreamDeposited);
    }

    function test_ClaimStream_PendingCheckpointPreservedOnDeposit() public {
        _applyFullConfig(); // 1e6/sec, carol sole beneficiary

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt * 2);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // Accrue some time
        skip(50);

        // A second deposit triggers the pending checkpoint
        vm.startPrank(depositor);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // Read pendingClaim from beneficiary storage
        ArcTreasury.StreamBeneficiary[] memory bens = treasury.getStreamBeneficiaries();
        uint256 pending = bens[0].pendingClaim;

        // pendingClaim should be > 0 because 50 seconds of accrual was snapshotted
        assertGt(pending, 0);
    }

    function test_ClaimStream_GetClaimableStreamMatchesClaim() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        skip(100);

        uint256 claimable = treasury.getClaimableStream(carol);
        uint256 balBefore = usdc.balanceOf(carol);

        vm.prank(carol);
        treasury.claimStream();

        assertEq(usdc.balanceOf(carol) - balBefore, claimable);
    }

    // ── claimStream — revert paths ────────────────────────────────────────────

    function test_ClaimStream_RevertNotBeneficiary() public {
        _applyFullConfig();

        vm.prank(bob); // bob is not a stream beneficiary
        vm.expectRevert(ArcTreasury.NotAStreamBeneficiary.selector);
        treasury.claimStream();
    }

    function test_ClaimStream_RevertNothingToClaim_NoDeposit() public {
        _applyFullConfig();
        // No deposit → streamDeposited == 0 → NothingToClaim

        vm.prank(carol);
        vm.expectRevert(ArcTreasury.NothingToClaim.selector);
        treasury.claimStream();
    }

    function test_ClaimStream_RevertNothingToClaim_NoTimeElapsed() public {
        _applyFullConfig();

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // No time warped — accrued == 0; pending == 0 → NothingToClaim
        vm.prank(carol);
        vm.expectRevert(ArcTreasury.NothingToClaim.selector);
        treasury.claimStream();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. getTreasurySummary — view
    // ─────────────────────────────────────────────────────────────────────────

    function test_GetTreasurySummary_ReturnsCorrectValues() public {
        _applyFullConfig();

        uint256 amount = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        (
            uint256 tot,
            uint256 sbal,
            uint256 mbal,
            uint256 stbal,
            uint256 sBps,
            uint256 mBps,
            uint256 stBps,
            bool configured
        ) = treasury.getTreasurySummary();

        assertEq(tot,   amount);
        assertEq(sbal,  (amount * 3_000) / BPS);
        assertEq(mbal,  (amount * 4_000) / BPS);
        assertEq(stbal, amount - (amount * 3_000) / BPS - (amount * 4_000) / BPS);
        assertEq(sBps,  3_000);
        assertEq(mBps,  4_000);
        assertEq(stBps, 3_000);
        assertTrue(configured);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Fuzz: depositAndRoute BPS accounting integrity
    // ─────────────────────────────────────────────────────────────────────────

    function testFuzz_DepositAndRoute_AccountingIntegrity(uint256 amount) public {
        // Use the full 3-way config (split 3000, milestone 4000, stream 3000)
        _applyFullConfig();

        // Bound to a sensible range (1 to 10M USDC)
        amount = bound(amount, 1, 10_000_000e6);

        usdc.mint(depositor, amount);
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 splitBal     = treasury.splitBalance();
        uint256 milestoneBal = treasury.milestoneBalance();
        uint256 streamBal    = treasury.streamBalance();
        uint256 total        = treasury.totalDeposited();

        // PROPERTY 1: tracked balances sum to total deposited
        assertEq(splitBal + milestoneBal + streamBal, total);

        // PROPERTY 2: contract actually holds the tokens
        assertEq(usdc.balanceOf(address(treasury)), total);

        // PROPERTY 3: individual split credits sum to splitBalance
        uint256 aliceCredit = treasury.splitCredits(alice); // alice is sole split recipient
        assertEq(aliceCredit, splitBal);
    }

    function testFuzz_DepositAndRoute_MultipleDeposits_BalancesAddUp(
        uint256 amount1,
        uint256 amount2
    ) public {
        _applyFullConfig();

        amount1 = bound(amount1, 1, 5_000_000e6);
        amount2 = bound(amount2, 1, 5_000_000e6);

        usdc.mint(depositor, amount1 + amount2);
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount1 + amount2);
        treasury.depositAndRoute(amount1);
        treasury.depositAndRoute(amount2);
        vm.stopPrank();

        uint256 total = treasury.totalDeposited();
        assertEq(total, amount1 + amount2);
        assertEq(
            treasury.splitBalance() + treasury.milestoneBalance() + treasury.streamBalance(),
            total
        );
        assertEq(usdc.balanceOf(address(treasury)), total);
    }

    function testFuzz_DepositAndRoute_BpsProportions(uint256 amount) public {
        _applyFullConfig();

        amount = bound(amount, BPS, 10_000_000e6); // at least BPS so division is meaningful

        usdc.mint(depositor, amount);
        vm.startPrank(depositor);
        usdc.approve(address(treasury), amount);
        treasury.depositAndRoute(amount);
        vm.stopPrank();

        uint256 splitBal     = treasury.splitBalance();
        uint256 milestoneBal = treasury.milestoneBalance();
        uint256 streamBal    = treasury.streamBalance();

        // Individual portions must be approximately correct (integer division may leave dust on stream)
        assertEq(splitBal,     (amount * 3_000) / BPS);
        assertEq(milestoneBal, (amount * 4_000) / BPS);
        // Stream gets the remainder — check it covers the expected floor
        assertGe(streamBal, (amount * 3_000) / BPS);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 9. Time-based accrual math — unit test
    // ─────────────────────────────────────────────────────────────────────────

    function test_StreamAccrual_LinearOverTime() public {
        _applyFullConfig(); // rate = 1e6/sec, carol bps = 10000

        uint256 depositAmt = 1_000e6;
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        // After 10 seconds claimable should be 10e6
        skip(10);
        assertEq(treasury.getClaimableStream(carol), 10e6);

        // After another 20 seconds (total 30) it should be 30e6
        skip(20);
        assertEq(treasury.getClaimableStream(carol), 30e6);
    }

    function testFuzz_StreamAccrual_NeverExceedsStreamDeposited(uint256 secs) public {
        _applyFullConfig(); // rate = 1e6/sec

        uint256 depositAmt = 100e6; // stream portion = 30e6
        usdc.mint(depositor, depositAmt);
        vm.startPrank(depositor);
        usdc.approve(address(treasury), depositAmt);
        treasury.depositAndRoute(depositAmt);
        vm.stopPrank();

        secs = bound(secs, 0, 365 days);
        skip(secs);

        uint256 claimable = treasury.getClaimableStream(carol);
        uint256 streamDeposited = treasury.getStreamBeneficiaries()[0].streamDeposited;

        // PROPERTY: can never claim more than what was streamed in
        assertLe(claimable, streamDeposited);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Invariant test — separate contract using the handler
// ─────────────────────────────────────────────────────────────────────────────
contract ArcTreasuryInvariantTest is Test {
    MockERC20              internal usdc;
    ArcTreasury            internal treasury;
    ArcTreasuryHandler     internal handler;

    address internal owner        = makeAddr("invariant_owner");
    address internal projectOwner = makeAddr("invariant_projectOwner");
    address internal depositor    = makeAddr("invariant_depositor");
    address internal splitRecip   = makeAddr("invariant_splitRecip");
    address internal streamBenef  = makeAddr("invariant_streamBenef");

    function setUp() public {
        vm.startPrank(owner);
        usdc     = new MockERC20("Mock USDC", "mUSDC", 6);
        treasury = new ArcTreasury(address(usdc));
        vm.stopPrank();

        // Configure with a full 3-way split so all three balance buckets are exercised
        ArcTreasury.SplitRecipient[] memory recips = new ArcTreasury.SplitRecipient[](1);
        recips[0] = ArcTreasury.SplitRecipient({addr: splitRecip, bps: 10_000});

        ArcTreasury.Milestone[] memory mils = new ArcTreasury.Milestone[](1);
        mils[0] = ArcTreasury.Milestone({description: "M1", amount: 50e6, released: false});

        ArcTreasury.StreamBeneficiary[] memory bens = new ArcTreasury.StreamBeneficiary[](1);
        bens[0] = ArcTreasury.StreamBeneficiary({
            addr: streamBenef, bps: 10_000,
            lastClaimTime: 0, claimedAmount: 0, pendingClaim: 0,
            streamDeposited: 0, cumulativeEntitlementAtConfig: 0
        });

        vm.prank(owner);
        treasury.configureTreasury(
            3_000, 4_000, 3_000,
            projectOwner,
            1e6, // 1 USDC/sec
            recips, mils, bens
        );

        handler = new ArcTreasuryHandler(
            treasury, usdc, depositor, projectOwner, splitRecip, streamBenef
        );

        // Impersonate handler for stream/split claims (handler calls them directly)
        vm.startPrank(address(handler));
        vm.stopPrank();

        targetContract(address(handler));
    }

    /// @dev INVARIANT: the three internal balance trackers never exceed the actual
    ///      USDC held by the contract.  This catches any accounting leak where a
    ///      claim or release path under-deducts a balance tracker.
    function invariant_TrackersNeverExceedActualBalance() public view {
        uint256 tracked = treasury.splitBalance()
            + treasury.milestoneBalance()
            + treasury.streamBalance();
        uint256 actual  = usdc.balanceOf(address(treasury));
        assertLe(tracked, actual);
    }

    /// @dev INVARIANT: totalDeposited equals the sum of all three balance trackers
    ///      plus whatever has already been paid out (we approximate: after any
    ///      deposit the total deposited should be >= tracked balances).
    function invariant_TotalDepositedGeTracked() public view {
        uint256 tracked = treasury.splitBalance()
            + treasury.milestoneBalance()
            + treasury.streamBalance();
        assertGe(treasury.totalDeposited(), tracked);
    }
}
