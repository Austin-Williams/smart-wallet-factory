# smart-wallet-factory
Factory for creating and tracking CHI-enabled smart wallets

## WARNING
This code has not been audited or thoroughly tested. Don't use it with more money than you are happy losing. Seriously.

## What

This is a factory that anyone can use to create smart wallets.

The smart wallets it creates:

1. Allows the owner to have the wallet call any function on any contract with any data and any value sent. This is done via the `execute` function.
2. Allows the owner to make several calls to several contracts in a single transaction. This is done via the `executeMany` function. (E.g., The owner can use this feature to deposit and bond ESD in a single transaction, or perform any other collection of actions they want to happen atomically).
3. Allows the owner to transfer ownership to another address. This is done via a secure "handshake" to prevent accidental loss of wallets. The owner "offers" ownership to another address (via the `offerOwnership` function), and the ownership transfer happens only when the new address explicitly accepts the offer (via the `takeOwnership` function).
4. Are CHI-enabled, so the owners can (optionally) do all the above while using CHI tokens to reduce gas costs during times of high gas prices. This feature is entirely optional, non-blocking, and has no effect on users who don't use CHI.
4. For UX convenience, and so users can more esily keep track of which wallets they own, the factory contract keeps a registry that maps every address to the set of wallets they own.

## Why

Initially created with ESD in mind, I wanted a "smart ESD wallet" that could allow me to:

1. Sell my bonded ESD or LP position by selling my _entire wallet_. (It is otherwise non-trivial to quickly divest of bonded ESD or LP).
2. Claim and "reinvest" LP rewards in a single transaction.
3. Deposit and bond in a single transaction.
4. "Bypass" the various usability issues realted to ESD timelocks. It is known that this can be done by using multiple wallets, and I wanted an easy way to create and keep track of multiple ESD wallets without having to manage several different keys.

Shortly after coding it up, though, I realized this pattern is useful in general, and so made it very generic (not ESD-specific).
