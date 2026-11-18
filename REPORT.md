TARGET
DepositPool shared implementation 0xdB10dAEF167eA2233Ba6811457dD24D676FbD670 (Appendix A, Ethereum), as deployed behind the wBTC pool 0xdE283F8309Fd1AA46c95d299f6B8310716277A42, the USDC pool 0x6cCE082851Add4c535352f596662521B4De4750E, and the USDT pool 0x3B51989212BEdaB926794D6bf8e9E991218cf116: referrer tier logic in ReferrerLib (getReferrerMultiplier / applyReferrerTier) and the per-pool referrerTiers configuration read through the pool. Verified source: contracts/capital-protocol/DepositPool.sol and its libraries (Sourcify, implementation match; repo file byte-identical).

INVARIANT
Referrer tier thresholds and multipliers are denominated in the pool's deposit token. A referrer whose referred stake crosses a tier threshold earns that tier's documented weight (3% / 5% / 10% / 15% of the referred amount as virtualAmountStaked) in every pool, as it does in the stETH and wETH pools.

IMPACT
The tier thresholds are stored 1e18-normalised but are compared against amountStaked accumulated in RAW token units. In the 18-decimal pools (stETH, wETH) the two scales coincide and tiers work. In the other three pools they never can: the wBTC pool's tier-0 threshold is 3.5e16 raw units = 350,000,000 WBTC, about 16.7x the entire Bitcoin supply, while the pool holds 0.103 WBTC; the USDC and USDT pools' tier-0 threshold is 4e21 raw units = 4 quadrillion tokens, while the USDC pool holds 427,785 USDC in total. Result: getReferrerMultiplier always returns 0 in the wBTC, USDC, and USDT pools, and every referrer in 3 of the 5 Capital pools earns exactly zero tier rewards, permanently, regardless of volume. Demonstrated on a fork: a 250,000 USDC referred stake (which should reach the top tier) books amountStaked 250,000,000,000 with virtualAmountStaked = 0 and getLatestReferrerReward = 0; the intended virtual weight of 37,500 USDC (15% of 250,000) is 4.22% of the USDC pool's total reward weight, paid as 0. The same zero applies proportionally to all referred volume in these pools: the entire 3%-15% tier leg of referrer compensation is void in 3 of 5 pools while the protocol advertises and configures it. CVSS 3.1: 5.3 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N).

PRECONDITIONS
None beyond normal use: any user stakes in the wBTC, USDC, or USDT DepositPool naming a referrer. No privileged role, no attacker action, and no special timing is required; the loss is the protocol's steady state in those pools.

ATTACK
1. Referrer R recruits a staker S for the USDC pool (the failure is identical in the wBTC and USDT pools).
2. S stakes 250,000 USDC into the USDC DepositPool naming R as referrer (normal deposit flow).
3. The pool accumulates R's amountStaked in raw units: 250,000,000,000 (250,000 x 10^6).
4. ReferrerLib compares amountStaked against tier thresholds stored 1e18-normalised; tier 0 alone requires 4e21 raw units.
5. No tier is reached: getReferrerMultiplier(R) returns 0 and applyReferrerTier credits virtualAmountStaked = 0.
6. At distribution, R's reward weight from tiers is 0; R receives no tier rewards for this or any volume, forever, in all three pools.
7. Control in the PoC: the identical flow in the stETH pool (18 decimals) credits the documented 15% top-tier weight (9.75 stETH on a 65 stETH referred stake), proving the defect is the unit mismatch in the low-decimal pools, not the tier design.

POC
Public Foundry project (linked repo): Ethereum mainnet fork via vm.createSelectFork, pinned blocks 26,440,460 / 26,440,465 / 26,440,469 across runs, run with `forge test`. Tests stake through the real pool contracts (stETH funded via the unprivileged Lido submit() route; USDC via fork deal()), then assert on-chain state: for the USDC pool, amountStaked = 250,000,000,000 while virtualAmountStaked = 0, getReferrerMultiplier = 0, getLatestReferrerReward = 0; the stETH control asserts the documented non-zero tier credit. Suite passes 3/3 runs at the pinned blocks. No owner/admin/multisig is impersonated. Live thresholds and multipliers were additionally read directly from the deployed pools (referrerTiers(0,i)) and cross-checked with cast.

FIX
Normalise before comparing: store per-pool tier thresholds in the deposit token's raw units at pool configuration time, or scale amountStaked to 1e18 (amountStaked * 10^(18 - tokenDecimals)) inside getReferrerMultiplier / applyReferrerTier before the threshold comparison. Add a configuration-time invariant that tier 0's threshold must be reachable below the pool's plausible TVL, and a fork test per pool decimals class (18, 8, 6) asserting a tier-0 crossing credits non-zero virtualAmountStaked.
