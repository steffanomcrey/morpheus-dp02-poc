// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

interface IDepositPool {
    function stake(uint256 rewardPoolIndex_, uint256 amount_, uint128 claimLockEnd_, address referrer_) external;
    function referrersData(address referrer_, uint256 idx_) external view returns (uint256 amountStaked, uint256 virtualAmountStaked, uint256 rate, uint256 pendingRewards, uint128 lastClaim);
    function getReferrerMultiplier(uint256 idx_, address referrer_) external view returns (uint256);
    function getLatestReferrerReward(uint256 idx_, address user_) external view returns (uint256);
    function referrerTiers(uint256 idx_, uint256 tier_) external view returns (uint256 amount, uint256 multiplier);
    function rewardPoolsData(uint256 idx_) external view returns (uint128 lastUpdate, uint256 rate, uint256 totalVirtualDeposited);
}

interface IStETH {
    function submit(address referral_) external payable returns (uint256);
    function balanceOf(address a_) external view returns (uint256);
    function approve(address spender_, uint256 amount_) external returns (bool);
}

interface IERC20 {
    function approve(address spender_, uint256 amount_) external returns (bool);
    function balanceOf(address a_) external view returns (uint256);
}

contract DPTest is Test {
    address constant STETH_POOL = 0x47176B2Af9885dC6C4575d4eFd63895f7Aaa4790;
    address constant USDC_POOL = 0x6cCE082851Add4c535352f596662521B4De4750E;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant DISTRIBUTOR = 0xDf1AC1AC255d91F5f4B1E3B4Aef57c5350F64C7A;
    uint256 constant PRECISION = 1e25;
    uint256 constant BLOCK = 26440469;

    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com", BLOCK);
    }

    function _fundStETH(address who_, uint256 ethAmount_) internal returns (uint256 bal_) {
        vm.deal(who_, ethAmount_);
        vm.prank(who_);
        IStETH(STETH).submit{value: ethAmount_}(address(0));
        bal_ = IStETH(STETH).balanceOf(who_);
    }

    // DP-01: live tier3 stake of 65 stETH (above the 62.5 tier3 threshold, allowing for the 1-wei stETH booking rounding).
    // Hypothesis claimed virtual = amount * 150 (9,750 stETH at 65). Live tier3 multiplier = 1.5e24, so code yields 65 * 1.5e24 / 1e25 = 9.75 stETH (15%).
    function testDP01_stETH_virtualIs15PercentNot150x() public {
        (uint256 t3amt, uint256 t3mult) = IDepositPool(STETH_POOL).referrerTiers(0, 3);
        console.log("tier3 threshold", t3amt);
        console.log("tier3 multiplier", t3mult);
        assertEq(t3amt, 62.5 ether, "tier3 threshold changed");
        assertEq(t3mult, 1500000000000000000000000, "tier3 multiplier is 1.5e24 (15% on 1e25 scale), not 1.5e27");

        address S = makeAddr("stakerDP01");
        address R = makeAddr("referrerDP01");
        uint256 bal = _fundStETH(S, 100 ether);
        assertGt(bal, 65 ether, "stETH funding failed");

        (, , uint256 totalVirtBefore) = IDepositPool(STETH_POOL).rewardPoolsData(0);
        vm.startPrank(S);
        IStETH(STETH).approve(DISTRIBUTOR, 65 ether);
        IDepositPool(STETH_POOL).stake(0, 65 ether, 0, R);
        vm.stopPrank();

        (uint256 amountStaked, uint256 virtualStaked, , , ) = IDepositPool(STETH_POOL).referrersData(R, 0);
        console.log("amountStaked", amountStaked);
        console.log("virtualAmountStaked", virtualStaked);
        // stETH measured-transfer rounding: amount booked can differ from 62.5 ether by a few wei
        assertApproxEqAbs(amountStaked, 65 ether, 100, "amountStaked ~65 stETH (1 wei stETH rounding)");
        uint256 intended = (amountStaked * t3mult) / PRECISION; // 15% of referred amount
        assertEq(virtualStaked, intended, "virtual equals amount * multiplier / PRECISION with live multiplier");
        assertApproxEqAbs(virtualStaked, 9.75 ether, 100, "virtual is 9.75 stETH (15% of 65), the documented percentage");
        assertTrue(virtualStaked < amountStaked, "virtual is a fraction of referred amount, NOT inflated");
        assertTrue(virtualStaked != amountStaked * 150, "virtual is NOT the hypothesised 150x figure (9375 stETH)");
        assertEq(IDepositPool(STETH_POOL).getReferrerMultiplier(0, R), t3mult, "public multiplier view returns 1.5e24");
        (, , uint256 totalVirtAfter) = IDepositPool(STETH_POOL).rewardPoolsData(0);
        uint256 tvDelta = totalVirtAfter - totalVirtBefore;
        console.log("totalVirtualDeposited delta", tvDelta);
        assertTrue(tvDelta >= virtualStaked, "referrer virtual was added into totalVirtualDeposited");
        assertTrue(tvDelta < virtualStaked + amountStaked * 2, "totalVirtual delta is referrer virtual plus staker own ~1.01x virtual only, no 150x inflation");
    }

    // DP-01 control + tier0: 2 stETH referred at tier0 (multiplier 3e23) yields 0.06 stETH virtual (3%).
    // (A stake of exactly 1.0 stETH books 1 wei below the tier0 threshold due to Lido rounding and yields 0; observed in attempt 2, recorded in VERDICT.)
    // Control with referrer = address(0): no referrer leg is created at all.
    function testDP01_control_tier0AndNoReferrer() public {
        address S = makeAddr("stakerTier0");
        address R = makeAddr("referrerTier0");
        _fundStETH(S, 10 ether);
        vm.startPrank(S);
        IStETH(STETH).approve(DISTRIBUTOR, 2 ether);
        IDepositPool(STETH_POOL).stake(0, 2 ether, 0, R);
        vm.stopPrank();
        (uint256 amountStaked, uint256 virtualStaked, , , ) = IDepositPool(STETH_POOL).referrersData(R, 0);
        console.log("tier0 amountStaked", amountStaked);
        console.log("tier0 virtualAmountStaked", virtualStaked);
        assertApproxEqAbs(virtualStaked, 0.06 ether, 100, "tier0 virtual is 3% of 2 stETH, not 30x");

        address S2 = makeAddr("stakerNoRef");
        _fundStETH(S2, 10 ether);
        vm.startPrank(S2);
        IStETH(STETH).approve(DISTRIBUTOR, 1 ether);
        IDepositPool(STETH_POOL).stake(0, 1 ether, 0, address(0));
        vm.stopPrank();
        (uint256 amt0, uint256 virt0, , , ) = IDepositPool(STETH_POOL).referrersData(address(0), 0);
        assertEq(amt0, 0, "control: no referrer, no amountStaked");
        assertEq(virt0, 0, "control: no referrer, no virtual");
    }

    // DP-02: USDC pool. Intended (1e18-normalised) top tier = 250,000 USDC, tier0 = 4,000 USDC.
    // Live stored tier0 threshold = 4e21 raw units; a 250,000 USDC stake is 2.5e11 raw, far below every tier.
    function testDP02_USDC_tiersUnreachable() public {
        (uint256 t0amt, uint256 t0mult) = IDepositPool(USDC_POOL).referrerTiers(0, 0);
        console.log("USDC tier0 threshold raw", t0amt);
        console.log("USDC tier0 multiplier", t0mult);
        assertEq(t0amt, 4000000000000000000000, "USDC tier0 threshold stored as 4e21 raw");
        assertEq(t0mult, 300000000000000000000000, "USDC tier0 multiplier 3e23");

        address S = makeAddr("stakerUSDC");
        address R = makeAddr("referrerUSDC");
        deal(USDC, S, 250_000e6);
        assertEq(IERC20(USDC).balanceOf(S), 250_000e6, "USDC deal failed");
        vm.startPrank(S);
        IERC20(USDC).approve(DISTRIBUTOR, 250_000e6);
        IDepositPool(USDC_POOL).stake(0, 250_000e6, 0, R);
        vm.stopPrank();

        (uint256 amountStaked, uint256 virtualStaked, , , ) = IDepositPool(USDC_POOL).referrersData(R, 0);
        console.log("USDC amountStaked raw", amountStaked);
        console.log("USDC virtualAmountStaked raw", virtualStaked);
        assertEq(amountStaked, 250_000e6, "referrer amountStaked booked in raw 6-dec units");
        assertEq(virtualStaked, 0, "DP-02: virtual is 0 despite referring the intended top-tier 250,000 USDC");
        assertEq(IDepositPool(USDC_POOL).getReferrerMultiplier(0, R), 0, "DP-02: effective referrer multiplier is 0");
        assertEq(IDepositPool(USDC_POOL).getLatestReferrerReward(0, R), 0, "DP-02: referrer reward is 0");
    }
}
