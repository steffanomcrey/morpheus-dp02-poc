# PoC for DP-02 (Morpheus bug bounty)

Foundry fork test suite against the deployed DepositPool contracts, in the program's required format.
The suite also contains the stETH control used to falsify the companion DP-01 hypothesis.

Run (one command, from a clean clone):

    forge test

Forks are created in-test via vm.createSelectFork against a public Ethereum RPC with pinned blocks.
No owner/admin/multisig impersonation. See ../REPORT.md for the finding and ../EVIDENCE.md for
live-state evidence and run logs.
