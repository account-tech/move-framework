/// Members can create multiple vaults with different balances and managers (using roles).
/// This allows for a more flexible and granular way to manage funds.

module account_actions::vault;

// === Imports ===

use std::{
    string::String,
    type_name::{Self, TypeName},
};
use sui::{
    bag::{Self, Bag},
    balance::Balance,
    coin::{Self, Coin},
};
use account_protocol::{
    account::{Account, Auth},
    intents::{Expired, Intent},
    executable::Executable,
    version_witness::VersionWitness,
};
use account_actions::version;

// === Errors ===

const EVaultNotEmpty: u64 = 0;

// === Structs ===

/// Dynamic Field key for the Vault.
public struct VaultKey(String) has copy, drop, store;
/// Dynamic field holding a budget with different coin types, key is name
public struct Vault has store {
    // heterogeneous array of Balances, TypeName -> Balance<CoinType>
    bag: Bag
}

/// Action to deposit an amount of this coin to the targeted Vault.
public struct DepositAction<phantom CoinType> has store {
    // vault name
    name: String,
    // exact amount to be deposited
    amount: u64,
}
/// Action to be used within intent making good use of the returned coin, similar to owned::withdraw.
public struct SpendAction<phantom CoinType> has store {
    // vault name
    name: String,
    // amount to withdraw
    amount: u64,
}

// === Public Functions ===

/// Authorized address can open a vault.
public fun open<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);

    account.add_managed_data(VaultKey(name), Vault { bag: bag::new(ctx) }, version::current());
}

/// Deposits coins owned by a an authorized address into a vault.
public fun deposit<Config, CoinType: drop>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String, 
    coin: Coin<CoinType>, 
) {
    account.verify(auth);

    let vault: &mut Vault = 
        account.borrow_managed_data_mut(VaultKey(name), version::current());

    if (vault.coin_type_exists<CoinType>()) {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::with_defining_ids<CoinType>());
        balance_mut.join(coin.into_balance());
    } else {
        vault.bag.add(type_name::with_defining_ids<CoinType>(), coin.into_balance());
    };
}

/// Closes the vault if empty.
public fun close<Config>(
    auth: Auth,
    account: &mut Account<Config>,
    name: String,
) {
    account.verify(auth);

    let Vault { bag } = 
        account.remove_managed_data(VaultKey(name), version::current());
    assert!(bag.is_empty(), EVaultNotEmpty);
    bag.destroy_empty();
}

/// Returns true if the vault exists.
public fun has_vault<Config>(
    account: &Account<Config>, 
    name: String
): bool {
    account.has_managed_data(VaultKey(name))
}

/// Returns a reference to the vault.
public fun borrow_vault<Config>(
    account: &Account<Config>, 
    name: String
): &Vault {
    account.borrow_managed_data(VaultKey(name), version::current())
}

/// Returns the number of coin types in the vault.
public fun size(vault: &Vault): u64 {
    vault.bag.length()
}

/// Returns true if the coin type exists in the vault.
public fun coin_type_exists<CoinType: drop>(vault: &Vault): bool {
    vault.bag.contains(type_name::with_defining_ids<CoinType>())
}

/// Returns the value of the coin type in the vault.
public fun coin_type_value<CoinType: drop>(vault: &Vault): u64 {
    vault.bag.borrow<TypeName, Balance<CoinType>>(type_name::with_defining_ids<CoinType>()).value()
}

// Intent functions

/// Creates a DepositAction and adds it to an intent.
public fun new_deposit<Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>,
    name: String,
    amount: u64,
    intent_witness: IW,
) {
    intent.add_action(DepositAction<CoinType> { name, amount }, intent_witness);
}

/// Processes a DepositAction and deposits a coin to the vault.
public fun do_deposit<Config, Outcome: store, CoinType: drop, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    coin: Coin<CoinType>,
    version_witness: VersionWitness,
    intent_witness: IW,
) {
    executable.intent().assert_is_account(account.addr());

    let action: &DepositAction<CoinType> = executable.next_action(intent_witness);
    assert!(action.amount == coin.value());
        
    let vault: &mut Vault = account.borrow_managed_data_mut(VaultKey(action.name), version_witness);
    if (!vault.coin_type_exists<CoinType>()) {
        vault.bag.add(type_name::with_defining_ids<CoinType>(), coin.into_balance());
    } else {
        let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::with_defining_ids<CoinType>());
        balance_mut.join(coin.into_balance());
    };
}

/// Deletes a DepositAction from an expired intent.
public fun delete_deposit<CoinType>(expired: &mut Expired) {
    let DepositAction<CoinType> { .. } = expired.remove_action();
}

/// Creates a SpendAction and adds it to an intent.
public fun new_spend<Outcome, CoinType, IW: drop>(
    intent: &mut Intent<Outcome>,
    name: String,
    amount: u64,
    intent_witness: IW,
) {
    intent.add_action(SpendAction<CoinType> { name, amount }, intent_witness);
}

/// Processes a SpendAction and takes a coin from the vault.
public fun do_spend<Config, Outcome: store, CoinType: drop, IW: drop>(
    executable: &mut Executable<Outcome>,
    account: &mut Account<Config>,
    version_witness: VersionWitness,
    intent_witness: IW,
    ctx: &mut TxContext
): Coin<CoinType> {
    executable.intent().assert_is_account(account.addr());
    
    let action: &SpendAction<CoinType> = executable.next_action(intent_witness);
        
    let vault: &mut Vault = account.borrow_managed_data_mut(VaultKey(action.name), version_witness);
    let balance_mut = vault.bag.borrow_mut<_, Balance<_>>(type_name::with_defining_ids<CoinType>());
    let coin = coin::take(balance_mut, action.amount, ctx);

    if (balance_mut.value() == 0) 
        vault.bag.remove<_, Balance<CoinType>>(type_name::with_defining_ids<CoinType>()).destroy_zero();
        
    coin
}

/// Deletes a SpendAction from an expired intent.
public fun delete_spend<CoinType>(expired: &mut Expired) {
    let SpendAction<CoinType> { .. } = expired.remove_action();
}
