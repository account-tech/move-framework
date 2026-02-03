module account_actions::owned_intents;

// === Imports ===

use std::string::String;
use sui::{
    transfer::Receiving,
    coin::Coin,
};
use account_protocol::{
    account::{Account, Auth},
    executable::Executable,
    owned,
    intents::Params,
    intent_interface,
};
use account_actions::{
    transfer as acc_transfer,
    vesting,
    vault,
    version,
};

// === Aliases ===

use fun intent_interface::process_intent as Account.process_intent;

// === Errors ===

const EObjectsRecipientsNotSameLength: u64 = 0;
const ECoinsRecipientsNotSameLength: u64 = 1;
const ENoVault: u64 = 2;

// === Structs ===

/// Intent Witness defining the intent to withdraw a coin and deposit it into a vault.
public struct WithdrawAndTransferToVaultIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw and transfer multiple objects.
public struct WithdrawObjectsAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw and transfer multiple coins.
public struct WithdrawCoinsAndTransferIntent() has copy, drop;
/// Intent Witness defining the intent to withdraw a coin and create a vesting.
public struct WithdrawAndVestIntent() has copy, drop;

// === Public functions ===

/// Creates a WithdrawAndTransferToVaultIntent and adds it to an Account.
public fun request_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    coin_amount: u64,
    vault_name: String,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(vault::has_vault(account, vault_name), ENoVault);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        "",
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        ctx,
        |intent, iw| {
            owned::new_withdraw_coin<_, _, CoinType, _>(intent, account, coin_amount, iw);
            vault::new_deposit<_, CoinType, _>(intent, vault_name, coin_amount, iw);
        }
    );
}

/// Executes a WithdrawAndTransferToVaultIntent, deposits a coin owned by the account into a vault.
public fun execute_withdraw_and_transfer_to_vault<Config, Outcome: store, CoinType: drop>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    coins: vector<Receiving<Coin<CoinType>>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndTransferToVaultIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw_coin(executable, account, coins, iw, ctx);
            vault::do_deposit(executable, account, coin, version::current(), iw);
        }
    );
}

/// Creates a WithdrawObjectsAndTransferIntent and adds it to an Account.
public fun request_withdraw_objects_and_transfer<Config, Outcome: store>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    object_ids: vector<ID>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(object_ids.length() == recipients.length(), EObjectsRecipientsNotSameLength);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        "",
        version::current(),
        WithdrawObjectsAndTransferIntent(),
        ctx,
        |intent, iw| object_ids.zip_do!(recipients, |object_id, recipient| {
            owned::new_withdraw_object(intent, account, object_id, iw);
            acc_transfer::new_transfer(intent, recipient, iw);
        })
    );
}

/// Executes a WithdrawObjectsAndTransferIntent, transfers an object owned by the account. Can be looped over.
public fun execute_withdraw_object_and_transfer<Config, Outcome: store, T: key + store>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    receiving: Receiving<T>,
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawObjectsAndTransferIntent(),
        |executable, iw| {
            let object = owned::do_withdraw_object(executable, account, receiving, iw);
            acc_transfer::do_transfer(executable, object, iw);
        }
    );
}

/// Creates a WithdrawCoinsAndTransferIntent and adds it to an Account.
public fun request_withdraw_coins_and_transfer<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    coin_amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();
    assert!(coin_amounts.length() == recipients.length(), ECoinsRecipientsNotSameLength);

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        "",
        version::current(),
        WithdrawCoinsAndTransferIntent(),
        ctx,
        |intent, iw| coin_amounts.zip_do!(recipients, |coin_amount, recipient| {
            owned::new_withdraw_coin<_, _, CoinType, _>(intent, account, coin_amount, iw);
            acc_transfer::new_transfer(intent, recipient, iw);
        })
    );
}

/// Executes a WithdrawCoinsAndTransferIntent, transfers a coin owned by the account. Can be looped over.
public fun execute_withdraw_coin_and_transfer<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    coins: vector<Receiving<Coin<CoinType>>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawCoinsAndTransferIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw_coin(executable, account, coins, iw, ctx);
            acc_transfer::do_transfer(executable, coin, iw);
        }
    );
}

/// Creates a WithdrawAndVestIntent and adds it to an Account.
public fun request_withdraw_and_vest<Config, Outcome: store, CoinType>(
    auth: Auth,
    account: &mut Account<Config>, 
    params: Params,
    outcome: Outcome,
    coin_amount: u64,
    start_timestamp: u64,
    end_timestamp: u64,
    recipient: address,
    ctx: &mut TxContext
) {
    account.verify(auth);
    params.assert_single_execution();

    intent_interface::build_intent!(
        account,
        params,
        outcome,
        "",
        version::current(),
        WithdrawAndVestIntent(),
        ctx,
        |intent, iw| {
            owned::new_withdraw_coin<_, _, CoinType, _>(intent, account, coin_amount, iw);
            vesting::new_vest(intent, start_timestamp, end_timestamp, recipient, iw);
        }
    );
}

/// Executes a WithdrawAndVestIntent, withdraws a coin and creates a vesting.
public fun execute_withdraw_and_vest<Config, Outcome: store, CoinType>(
    executable: &mut Executable<Outcome>, 
    account: &mut Account<Config>, 
    coins: vector<Receiving<Coin<CoinType>>>,
    ctx: &mut TxContext
) {
    account.process_intent!(
        executable,
        version::current(),
        WithdrawAndVestIntent(),
        |executable, iw| {
            let coin = owned::do_withdraw_coin(executable, account, coins, iw, ctx);
            vesting::do_vest(executable, coin, iw, ctx);
        }
    );
}