# DP-02 evidence

Scope enumeration: the target is an Appendix A entry: the shared DepositPool implementation 0xdB10dAEF167eA2233Ba6811457dD24D676FbD670 on Ethereum and three of its five Appendix A pool proxies (wBTC 0xdE283F8309Fd1AA46c95d299f6B8310716277A42, USDC 0x6cCE082851Add4c535352f596662521B4De4750E, USDT 0x3B51989212BEdaB926794D6bf8e9E991218cf116). The stETH pool 0x47176B2Af9885dC6C4575d4eFd63895f7Aaa4790 appears only as the working control.

Live-state reads (read-only eth_call vs ethereum-rpc.publicnode.com, block 26,440,410, batched and cross-checked with cast; raw output in the hunt workdir validation/DP-02/live-reads.txt):
- referrerTiers(0, i) multipliers: 3e23 / 5e23 / 1e24 / 1.5e24, i.e. the documented 3% / 5% / 10% / 15% on the PRECISION = 1e25 scale (IReferrer documents 1% = 0.01 x 10^25). Tiers themselves are configured as intended.
- Thresholds (1e18-normalised): stETH tiers at 1 / 2.5 / 25 / 62.5 tokens; wBTC tier 0 at 3.5e16 raw units = 350,000,000 WBTC; USDC/USDT tier 0 at 4e21 raw units = 4 quadrillion tokens.
- Pool totals for scale: wBTC pool holds 0.10297537 WBTC; USDC pool holds 427,785.15 USDC; USDT pool holds 4,738.99 USDT (recon live reads, RECON.md).

Reproduction: poc/ suite run at pinned fork blocks 26,440,460, 26,440,465, 26,440,469: 3/3 tests PASS in every run (full logs in the hunt workdir, validation/DP-01/poc-runs.txt, shared suite). Assertions: USDC referred stake of 250,000 USDC -> amountStaked 250,000,000,000, virtualAmountStaked 0, getReferrerMultiplier 0, getLatestReferrerReward 0; stETH control (65 stETH referred) -> virtualAmountStaked 9.75 stETH (the documented 15%), totalVirtual delta 75.4. The contrast isolates the unit mismatch as the root cause.

Companion falsification (same suite): the originally hypothesised stETH-side multiplier inflation (DP-01) was FALSIFIED by these same live reads; the deployed multipliers are on the documented scale. Only the threshold/unit leg (this report) survives.

Gate notes for the parent re-audit: before filing, grep the full Code4rena findings set and the Renascence V5 referral report for any "tier" mention (fence completeness); the hunt fence (recon/audit-fence.md) records the referral findings as the flat-1% self-referral class and the A11 H-1 referrer-replacement item, neither of which is this threshold unit mismatch. Informative-risk call is the parent's: the counter-argument is that a configured, advertised compensation leg paying exactly 0 in 3 of 5 pools, with a fork-quantified 4.22% reward-weight loss on a realistic book, is a quantified loss to a defined user class, not a cosmetic defect.

Full analysis: validation/DP-02/VERDICT.md in the hunt workdir. Threat model: recon/hypo-depositpool.md (DP-02, plus the coordinator errata appended to that file).
